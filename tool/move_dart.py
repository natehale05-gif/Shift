#!/usr/bin/env python3
"""Move Dart files inside lib/ and repair every import, in both directions.

Written after the same bug bit three separate waves of the R-series refactor:
it is not enough to repoint *references to* a moved file, you must also
recompute the moved file's *own* relative imports — and that recomputation has
to know about the other moves happening in the same batch, or it faithfully
resolves a path to where the target used to live.

Usage:
    tool/move_dart.py  old/path.dart=new/path.dart  [more...]

Paths are relative to lib/. Also rewrites `package:shift_ai/...` references
across lib/ and test/.
"""
import os, re, sys, posixpath, subprocess, glob

LIB = 'lib'
PKG = 'package:shift_ai/'


def main(pairs):
    moves = dict(p.split('=', 1) for p in pairs)

    for old, new in moves.items():
        src, dst = os.path.join(LIB, old), os.path.join(LIB, new)
        if not os.path.exists(src):
            sys.exit(f'error: {src} does not exist')
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        subprocess.run(['git', 'mv', src, dst], check=True)

    changed = 0
    for path in glob.glob('lib/**/*.dart', recursive=True) + \
                glob.glob('test/**/*.dart', recursive=True):
        in_lib = path.startswith('lib/')
        text = original = open(path).read()
        # Where this file sits *now*, and where it sat *before* the batch.
        here = posixpath.dirname(os.path.relpath(path, LIB if in_lib else 'test'))
        was = here
        for old, new in moves.items():
            if os.path.relpath(path, LIB) == new:
                was = posixpath.dirname(old)
                break

        text = text.replace(PKG + '', PKG)  # no-op, keeps intent explicit
        for old, new in moves.items():
            text = text.replace(PKG + old, PKG + new)

        if in_lib:
            # Relative imports: resolve against where the file *used* to be,
            # apply the moves map, then re-express from where it is now.
            def fix(m):
                target = posixpath.normpath(posixpath.join(was, m.group(1)))
                target = moves.get(target, target)
                if target.startswith('..'):
                    return m.group(0)
                return "'" + posixpath.relpath(target, here) + "'"
            text = re.sub(r"'((?:\.\./)*[a-z_0-9]+(?:/[a-z_0-9]+)*\.dart)'", fix, text)
            # Conditional-import branches are matched by the same pattern above,
            # so they are repaired too — R2b shipped a broken one because the
            # analyzer only resolves the default branch.

        if text != original:
            open(path, 'w').write(text)
            changed += 1
    print(f'moved {len(moves)} files, rewrote imports in {changed}')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
