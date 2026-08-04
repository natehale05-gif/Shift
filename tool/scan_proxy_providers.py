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


def main() -> int:
    client, server = dart_set(), js_keys()
    if client == server:
        print(f'proxyable providers agree ({len(client)}): '
              f'{", ".join(sorted(client))}')
        return 0

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
