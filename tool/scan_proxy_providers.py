#!/usr/bin/env python3
"""Keep the client's idea of what the proxy forwards in step with the proxy.

`lib/providers/proxyable.dart` lists the providers a
membership can pay for; `supabase/functions/_shared/upstream.js` decides which
ones the server will actually forward to. They are written in different
languages, deployed on different schedules, and read by nobody at the same
time — which is exactly the shape of a list that drifts.

Drift is silent and expensive. If the client believes a provider is covered and
the server does not forward it, routing picks that provider for a member with no
key of their own, the call goes out with no credential, and the provider answers
401 — reported to the member as a bad key, for a key they never had. The
opposite drift is milder but still wrong: a provider SHIFT is paying for that
nobody is offered.

Run from CI beside the other scans.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DART = ROOT / 'lib' / 'providers' / 'proxyable.dart'
JS = ROOT / 'supabase' / 'functions' / '_shared' / 'upstream.js'


def dart_set() -> set:
    text = DART.read_text()
    block = re.search(
        r'const Set<String> proxyableProviders = \{(.*?)\};', text, re.S)
    if not block:
        raise SystemExit(f'{DART.name}: could not find proxyableProviders')
    return set(re.findall(r"'([\w-]+)'", block.group(1)))


def js_keys() -> set:
    text = JS.read_text()
    block = re.search(r'const UPSTREAMS = \{(.*?)\n\};', text, re.S)
    if not block:
        raise SystemExit(f'{JS.name}: could not find UPSTREAMS')
    # Top-level keys only: two spaces of indent, then `name: {`. The nested
    # `host:` / `allow:` lines sit deeper, so indentation is enough to tell
    # them apart without parsing JavaScript.
    return set(re.findall(r'^  ([\w-]+): \{', block.group(1), re.M))


TOOLS = ROOT / 'lib' / 'providers' / 'clients' / 'anthropic_tools.dart'  # not built yet
PROXY = ROOT / 'supabase' / 'functions' / 'provider-proxy' / 'index.js'


def one(path: pathlib.Path, pattern: str, what: str) -> str:
    found = re.search(pattern, path.read_text())
    if not found:
        raise SystemExit(f'{path.name}: could not find {what}')
    return found.group(1)


def betas_agree() -> bool:
    """The code-execution beta identifier, which now lives in two languages.

    The client used to send `anthropic-beta` itself. It cannot on a managed
    call — the browser would preflight a header the proxy has not allowed —
    so the proxy sets it, reading the same `tools` out of the body. That means
    two copies of one string, and a mismatch is quiet: the provider rejects a
    tool the client believes it enabled, which reads as the model declining to
    run code rather than as a typo.
    """
    if not TOOLS.exists():
        # Said out loud rather than skipped silently. The app has no
        # code-execution tool yet, so there is no second copy to disagree with
        # the server's — but a check that quietly passes when it cannot run is
        # the shape this repository keeps getting bitten by.
        print('code-execution beta unchecked: the app has no tool for it yet')
        return True

    client = one(TOOLS, r"codeExecutionBeta = '([^']+)'", 'codeExecutionBeta')
    server = one(PROXY, r"CODE_EXECUTION_BETA = '([^']+)'", 'CODE_EXECUTION_BETA')
    if client == server:
        print(f'code-execution beta agrees: {client}')
        return True
    print(f'FAIL: code-execution beta differs — client {client!r}, '
          f'server {server!r}', file=sys.stderr)
    return False


def offered_is_covered(server: set) -> bool:
    """The app may offer fewer providers than the proxy serves, never more.

    Equality would be the wrong test: the proxy forwards eight and the app has
    wire clients for six, so a provider without a client yet is an honest gap
    rather than a fault.

    The direction that costs money is the other one. A provider the app offers
    and the server refuses sends a call out with no credential and answers 401,
    which reads to a member as a bad key rather than as a routing mistake.
    """
    client = dart_set()
    extra = client - server
    if not extra:
        print(f'offered providers are covered ({len(client)}): '
              f'{", ".join(sorted(client))}')
        return True

    print('FAIL: the app offers providers the proxy will not forward',
          file=sys.stderr)
    for name in sorted(extra):
        print(f'  {name}', file=sys.stderr)
    return False


def js_allow() -> dict:
    """`{provider: [(METHOD, path-prefix), ...]}` — the server's own allowlist.

    Same indentation trick as `js_keys`: each provider's block starts at two
    spaces, and its `allow:` array is the only one inside it.
    """
    text = JS.read_text()
    block = re.search(r'const UPSTREAMS = \{(.*?)\n\};', text, re.S)
    if not block:
        raise SystemExit(f'{JS.name}: could not find UPSTREAMS')

    allow = {}
    for match in re.finditer(
            r'^  ([\w-]+): \{(.*?)^  \},', block.group(1) + '\n  },', re.M | re.S):
        entries = re.search(r'allow: \[(.*?)\]', match.group(2), re.S)
        if not entries:
            raise SystemExit(f'{JS.name}: {match.group(1)} has no allow list')
        allow[match.group(1)] = [
            tuple(entry.split(' ', 1))
            for entry in re.findall(r"'([^']+)'", entries.group(1))
        ]
    return allow


# Which upstreams a client's path has to satisfy. `openai_*` serves every
# provider on that wire, which is how one missing prefix broke four.
CLIENT_SERVES = {
    'anthropic_text.dart': ['anthropic'],
    'gemini_text.dart': ['gemini'],
    'gemini_image.dart': ['gemini'],
    'openai_text.dart': ['openai', 'groq', 'mistral', 'openrouter'],
    'openai_image.dart': ['openai'],
}


def client_path(name: str):
    """The provider path a client sends, or None when it does not exist yet.

    A declared constant where there is one, and otherwise the literal in the
    managed arm — Gemini's path carries a model id, so it cannot be a constant
    and the prefix is what matters.
    """
    source = ROOT / 'lib' / 'providers' / 'clients' / name
    if not source.exists():
        return None

    text = source.read_text()
    declared = re.search(r"static const providerPath = '([^']+)'", text)
    if declared:
        return declared.group(1)
    return re.search(r"path: '\$\{base\.path\}(/[^'$]*)", text).group(1)


def managed_paths_reach_the_server(allow: dict) -> bool:
    """Every path a client sends through the proxy is one the proxy forwards.

    **This is the check that was missing.** The server's allowlist lives in this
    repository and nothing compared it to what the clients actually send, so
    `openai_text` and `openai_image` spent months sending `/chat/completions`
    and `/images/generations` against an allowlist wanting `/v1/...`. Every
    managed turn on OpenAI, Groq, Mistral and OpenRouter came back 403, and the
    app reported it as a rejected key.

    The `/v1` was dropped because the direct arm inherits it from the registry's
    `baseUrl` and the managed arm rebuilt the path from scratch. So the fix is
    one constant per client — and this is what stops the next one.
    """
    problems = []
    checked = 0
    for name, providers in CLIENT_SERVES.items():
        path = client_path(name)
        if path is None:
            continue

        for provider in providers:
            checked += 1
            permitted = any(
                method == 'POST' and path.startswith(prefix)
                for method, prefix in allow.get(provider, []))
            if not permitted:
                problems.append(f'  {name} sends {path!r}, which the proxy '
                                f'will not forward to {provider}')

    if problems:
        print('FAIL: a managed call would be refused by our own proxy',
              file=sys.stderr)
        for line in problems:
            print(line, file=sys.stderr)
        return False

    print(f'managed paths reach the server ({checked} client/provider pairs)')
    return True


def required_routes() -> dict:
    """`app/lib/providers/proxy_routes.dart` as `{provider: {'METHOD /prefix'}}`."""
    path = ROOT / 'lib' / 'providers' / 'proxy_routes.dart'
    if not path.exists():
        return {}

    block = re.search(
        r'const Map<String, List<String>> requiredProxyRoutes = \{(.*?)\n\};',
        path.read_text(), re.S)
    if not block:
        raise SystemExit('proxy_routes.dart: no requiredProxyRoutes')

    routes = {}
    for entry in re.finditer(r"'([\w-]+)': \[(.*?)\]", block.group(1), re.S):
        routes[entry.group(1)] = set(re.findall(r"'([^']+)'", entry.group(2)))
    return routes


def required_routes_are_a_mirror(allow: dict) -> bool:
    """The app's stated requirement matches what its clients actually send.

    `requiredProxyRoutes` is what the app asks a *running* server about, and a
    list nobody checks is the reason this whole wave exists. Two directions,
    both of which have to hold:

      * every path a client builds is covered by an entry — otherwise the app
        would report a server "current" while sending it something it refuses,
        which is worse than not asking;
      * every entry appears verbatim in this repository's own allowlist —
        otherwise the app asks for a route we never intended to serve, and a
        correctly-deployed server would be reported as behind.
    """
    routes = required_routes()
    if not routes:
        return True

    problems = []
    for name, providers in CLIENT_SERVES.items():
        path = client_path(name)
        if path is None:
            continue
        for provider in providers:
            covered = any(
                entry.startswith('POST ') and path.startswith(entry[5:])
                for entry in routes.get(provider, ()))
            if not covered:
                problems.append(f'  {name} sends {path!r} to {provider}, which '
                                f'requiredProxyRoutes does not claim')

    for provider, entries in routes.items():
        served = {f'{method} {prefix}' for method, prefix in allow.get(provider, [])}
        for entry in sorted(entries - served):
            problems.append(f'  requiredProxyRoutes asks {provider} for {entry!r}, '
                            f'which this repo\'s proxy does not allow')

    if problems:
        print('FAIL: requiredProxyRoutes is not a mirror of what the app sends',
              file=sys.stderr)
        for line in problems:
            print(line, file=sys.stderr)
        return False

    total = sum(len(entries) for entries in routes.values())
    print(f'required proxy routes mirror the clients ({total} routes)')
    return True


def main() -> int:
    server = js_keys()
    allow = js_allow()
    ok = (betas_agree() and offered_is_covered(server)
          and managed_paths_reach_the_server(allow)
          and required_routes_are_a_mirror(allow))
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
