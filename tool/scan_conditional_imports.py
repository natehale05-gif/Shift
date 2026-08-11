#!/usr/bin/env python3
"""Checks every conditional import pair in v1's `lib/` and v2's `app/lib/`.

The analyzer only ever resolves the **default** branch of a conditional
import. A stale path or a drifted name in the other branch therefore passes
`flutter analyze` cleanly and fails only at `flutter build web` -- which is
how R2b shipped a broken build. This closes that gap:

* both branch files must exist;
* every name the importing file actually uses must be declared by **both**
  branches, so one branch cannot quietly lose something the other provides.

A name declared in only one branch and used by nobody is fine and is not
reported -- the branches are allowed to differ, they just cannot differ in
what their importer depends on. Signature drift (same name, different
parameters) is still only caught by the build.

    python3 tool/scan_conditional_imports.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# **Both apps.** This scanned only v1 for the whole of the v2 rebuild, so every
# report of "N pairs clean" during it was true of v1 and silent about v2 --
# whose pairs key on `dart.library.js_interop` and are the ones most likely to
# be wrong, because `dart.library.html` is *false* under dart2wasm and picking
# the wrong arm raises nothing at all.
LIBS = [ROOT / "lib", ROOT / "app" / "lib"]

# Both keywords: `export` facades (open_url, file_intake) re-expose the whole
# branch, so they need a stricter check than `import` ones do. Captures the
# optional `as prefix` so prefixed uses can be resolved too.
CONDITIONAL = re.compile(
    r"\b(import|export)\s+'([^']+)'\s*"
    r"if\s*\(\s*dart\.library\.\w+\s*\)\s*'([^']+)'"
    r"(?:\s+as\s+(\w+))?\s*;"
)

# Top-level declarations only: anchored at column 0, and every run of
# whitespace inside a pattern is horizontal-only. `\s` would match newlines,
# letting a "return type" swallow the indentation of the next line and turn
# every indented call into a fake top-level declaration.
H = r"[ \t]"
DECLARATION = re.compile(
    r"^(?:abstract |base |final |interface |sealed )*"
    rf"(?:class|enum|mixin|extension type|extension|typedef){H}+(\w+)"
    # The return type must begin with a word character, so an indented call
    # cannot pass its own leading spaces off as one.
    rf"|^(?:[\w$<>?][\w$<>,?\[\] \t]*?{H}+)(\w+){H}*(?:<[\w\s,]+>)?{H}*\("
    rf"|^(?:const|final|late){H}+(?:[\w$<>,?\[\] \t]+{H}+)?(\w+){H}*="
    # Top-level getters. Without this the scanner cannot see one at all — and
    # a name it cannot see is a name it cannot report as missing, which is a
    # false pass rather than a gap. Found when one arm of a platform facade
    # declared a `const` and the other a getter: it flagged the getter as
    # absent, which was the right complaint for the wrong reason.
    rf"|^(?:[\w$<>?][\w$<>,?\[\] \t]*{H}+)?get{H}+(\w+)",
    re.MULTILINE,
)

KEYWORDS = {"if", "for", "while", "switch", "return", "assert", "await", "yield"}


def public_names(path: Path) -> set[str]:
    names = set()
    for match in DECLARATION.finditer(path.read_text()):
        name = next((g for g in match.groups() if g), None)
        if name and not name.startswith("_") and name not in KEYWORDS:
            names.add(name)
    return names


def used_names(text: str, prefix: str | None) -> set[str]:
    if prefix:
        return set(re.findall(rf"\b{re.escape(prefix)}\.(\w+)", text))
    return set(re.findall(r"\b([A-Za-z_$][\w$]*)\b", text))


def main() -> int:
    problems = []
    pairs = 0

    for lib in LIBS:
      if not lib.is_dir():
          continue
      for source in sorted(lib.rglob("*.dart")):
        text = source.read_text()
        for keyword, default_path, other_path, prefix in CONDITIONAL.findall(text):
            pairs += 1
            default = (source.parent / default_path).resolve()
            other = (source.parent / other_path).resolve()
            rel = source.relative_to(ROOT)

            missing = [p for p in (default, other) if not p.is_file()]
            if missing:
                problems += [f"{rel}: missing branch {p}" for p in missing]
                continue

            in_default = public_names(default)
            in_other = public_names(other)

            # An `export` facade re-exposes the branch wholesale, so callers
            # live in other files and every asymmetry is a real gap. An
            # `import` only has to satisfy this file.
            divergent = in_default ^ in_other
            if keyword == "import":
                divergent &= used_names(text, prefix or None)

            for name in sorted(divergent):
                have, lack = (
                    (default, other) if name in in_default else (other, default)
                )
                problems.append(
                    f"{rel}: '{name}' is declared in {have.name} "
                    f"but missing from {lack.name}"
                )

    for problem in problems:
        print(f"  {problem}")
    print(f"{pairs} conditional import pair(s) checked, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
