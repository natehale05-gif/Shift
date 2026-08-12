#!/usr/bin/env python3
"""Keep the client's idea of what the proxy forwards in step with the proxy.

`lib/providers/clients/proxyable_providers.dart` lists the providers a
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
DART = ROOT / 'lib' / 'providers' / 'clients' / 'proxyable_providers.dart'
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


TOOLS = ROOT / 'lib' / 'providers' / 'clients' / 'anthropic_tools.dart'
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
    client = one(TOOLS, r"codeExecutionBeta = '([^']+)'", 'codeExecutionBeta')
    server = one(PROXY, r"CODE_EXECUTION_BETA = '([^']+)'", 'CODE_EXECUTION_BETA')
    if client == server:
        print(f'code-execution beta agrees: {client}')
        return True
    print(f'FAIL: code-execution beta differs — client {client!r}, '
          f'server {server!r}', file=sys.stderr)
    return False


def v2_subset(server: set) -> bool:
    """v2's list may be smaller, but may not name something the server won't take.

    v1 must match the server exactly — it has a client for everything the proxy
    forwards. v2 is still being built and covers six of the eight, so equality
    would be the wrong test: it would fail for the honest reason that a client
    does not exist yet.

    What must hold is the direction that costs money. A provider v2 offers and
    the server refuses sends a call out with no credential and answers 401,
    which reads as a bad key rather than as a routing mistake. The other
    direction — the server would forward it, v2 does not ask — costs nothing but
    a feature nobody has yet.
    """
    path = ROOT / 'app' / 'lib' / 'providers' / 'proxyable.dart'
    if not path.exists():
        return True

    block = re.search(
        r'const Set<String> proxyableProviders = \{(.*?)\};',
        path.read_text(), re.S)
    if not block:
        raise SystemExit('app/lib/providers/proxyable.dart: no proxyableProviders')

    v2 = set(re.findall(r"'([\w-]+)'", block.group(1)))
    extra = v2 - server
    if not extra:
        print(f'v2 proxyable providers are covered ({len(v2)}): '
              f'{", ".join(sorted(v2))}')
        return True

    print('FAIL: v2 offers providers the proxy will not forward', file=sys.stderr)
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
    clients = ROOT / 'app' / 'lib' / 'providers' / 'clients'
    if not clients.is_dir():
        return True

    # Which upstreams a client's path has to satisfy. `openai_*` serves every
    # provider on that wire, which is how one missing prefix broke four.
    serves = {
        'anthropic_text.dart': ['anthropic'],
        'gemini_text.dart': ['gemini'],
        'gemini_image.dart': ['gemini'],
        'openai_text.dart': ['openai', 'groq', 'mistral', 'openrouter'],
        'openai_image.dart': ['openai'],
    }

    problems = []
    checked = 0
    for name, providers in serves.items():
        source = clients / name
        if not source.exists():
            continue

        # A declared constant, or the literal in the managed arm for the
        # clients whose path carries a model id and cannot be a constant.
        declared = re.search(
            r"static const providerPath = '([^']+)'", source.read_text())
        path = declared.group(1) if declared else re.search(
            r"path: '\$\{base\.path\}(/[^'$]*)", source.read_text()).group(1)

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


def main() -> int:
    client, server = dart_set(), js_keys()
    ok = (betas_agree() and v2_subset(server)
          and managed_paths_reach_the_server(js_allow()))

    if client == server:
        print(f'proxyable providers agree ({len(client)}): '
              f'{", ".join(sorted(client))}')
        return 0 if ok else 1

    print('FAIL: the client and the proxy disagree about what is covered',
          file=sys.stderr)
    for name in sorted(client - server):
        print(f'  offered to members but the server will not forward it: {name}',
              file=sys.stderr)
    for name in sorted(server - client):
        print(f'  the server forwards it but no member is offered it: {name}',
              file=sys.stderr)
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
