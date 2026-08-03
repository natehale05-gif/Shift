#!/usr/bin/env python3
"""Inline a function's `_shared` imports into one file.

The CI job in `.github/workflows/backend.yml` is how these deploy once the
repository has a Supabase access token, and it is the path that survives the
next edit. This is for the two cases where it cannot run: deploying through the
management API (which takes a file list, not a directory), and pasting into the
dashboard's editor — `provider-proxy` is six files, and pasting six files from a
phone is not a process.

    python3 tool/bundle_function.py provider-proxy                  -> provider-proxy.js
    python3 tool/bundle_function.py provider-proxy --deno           -> provider-proxy.deno.ts
    python3 tool/bundle_function.py provider-proxy --deno --lean    -> provider-proxy.lean.deno.ts

`--deno` appends the one line that makes the bundle a deployable entrypoint.
Everything above it is platform-neutral, which is the whole point of the
`(Request, ctx) => Response` shape: the adapter is a line, not a rewrite.

`--lean` drops whole-line comments, which halves `provider-proxy` from 32 KB to
16 KB. That matters only for the deploy paths where the file travels as one
literal string — a management-API call, or a paste — and where every byte is a
byte that can be transcribed wrong.

Deliberately dumb — it resolves relative imports of `../_shared/*.js`, strips
their `export` keywords, and concatenates in dependency order. It is not a
bundler and should not become one: the moment these functions need real
bundling, they need a real build step, and this script existing would only
delay noticing.

Because deploys now go through it, `supabase/functions/tests/bundle.test.js`
imports every bundle and drives a request through it. A name collision between
two inlined `_shared` files would otherwise be a production 500 that no other
test can see.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FUNCTIONS = ROOT / 'supabase' / 'functions'
OUT = ROOT / 'build' / 'functions'

IMPORT = re.compile(
    r"^import\s*\{([^}]*)\}\s*from\s*'(\.\./_shared/[\w.]+)';\s*$",
    re.MULTILINE,
)


def shared_source(path: pathlib.Path, seen: set) -> str:
    """The text of a `_shared` module, with its own imports resolved first."""
    if path in seen:
        return ''
    seen.add(path)

    text = path.read_text()
    prefix = ''
    for match in IMPORT.finditer(text):
        prefix += shared_source((FUNCTIONS / match.group(2)[3:]).resolve(), seen)

    body = IMPORT.sub('', text)
    # `export` means nothing once everything is in one scope, and leaving it
    # in is a syntax error outside a module.
    body = re.sub(r'^export\s+(?=(async\s+)?(function|const|class|let))', '',
                  body, flags=re.MULTILINE)
    return f'{prefix}\n// ---- {path.name} ----\n{body}\n'


# The line that turns a platform-neutral bundle into something Deno serves.
# `handle` is the exported name in every handler, so this is the same line for
# all of them — which is what makes the adapter a line rather than a rewrite.
DENO_ENTRY = (
    "\n// ---- deployed entrypoint ----\n"
    "Deno.serve((req) => handle(req, { env: Deno.env.toObject(), fetch }));\n"
)


def strip_comments(text: str) -> str:
    """Drops whole-line comments only.

    `--lean` exists because a bundle deployed through the management API has to
    travel as one literal string, and `provider-proxy` is 32 KB of which two
    thirds are prose. Halving it halves the surface for a transcription
    mistake, and the prose is not lost — it is in the repository, which is
    where it is read.

    **Whole-line only, deliberately.** A general comment stripper has to know
    which `//` is inside a string literal, and `upstream.js` is a file of
    URLs — `'https://api.anthropic.com'` is exactly the case that turns a
    careless regex into a corrupted deploy. A line whose first character is a
    comment marker is unambiguous, and `bundle.test.js` imports the lean output
    and drives a request through it, so a mistake here fails a test rather than
    a request.
    """
    out, in_block = [], False
    for line in text.splitlines():
        stripped = line.strip()
        if in_block:
            if '*/' in stripped:
                in_block = False
            continue
        if stripped.startswith('/*'):
            if '*/' not in stripped:
                in_block = True
            continue
        if stripped.startswith('//'):
            continue
        out.append(line)
    return re.sub(r'\n{3,}', '\n\n', '\n'.join(out)).strip() + '\n'


def bundle(name: str, deno: bool = False, lean: bool = False) -> pathlib.Path:
    entry = FUNCTIONS / name / 'index.js'
    if not entry.exists():
        raise SystemExit(f'No such function: {name}')

    text = entry.read_text()
    seen: set = set()
    shared = ''
    for match in IMPORT.finditer(text):
        shared += shared_source((FUNCTIONS / match.group(2)[3:]).resolve(), seen)

    # The entry's own exports are kept, unlike the shared modules' — the bundle
    # *is* a module, so `export const handle` is still meaningful at its top
    # level, and it is what lets `tests/bundle.test.js` import what ships and
    # drive a request through it. Stripping them here (as an earlier version
    # did) produced a file that deployed fine and could not be tested at all.
    body = IMPORT.sub('', text)

    text = (
        f'{shared}\n// ---- {name}/index.js ----\n{body}\n'
        f'{DENO_ENTRY if deno else ""}'
    )
    if lean:
        text = strip_comments(text)

    OUT.mkdir(parents=True, exist_ok=True)
    suffix = '.deno.ts' if deno else '.js'
    out = OUT / f'{name}{".lean" if lean else ""}{suffix}'
    out.write_text(
        f'// Generated by tool/bundle_function.py from '
        f'supabase/functions/{name}/ — do not edit.\n'
        f'// Regenerate rather than patching: this file is deployed, so an edit\n'
        f'// here is a change that exists only in production.\n'
        f'{text}'
    )
    return out


if __name__ == '__main__':
    flags = {'--deno', '--lean'}
    args = [a for a in sys.argv[1:] if a not in flags]
    if len(args) != 1:
        raise SystemExit(
            'usage: bundle_function.py <function-name> [--deno] [--lean]')
    print(
        bundle(
            args[0],
            deno='--deno' in sys.argv,
            lean='--lean' in sys.argv,
        ).relative_to(ROOT)
    )
