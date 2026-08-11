#!/usr/bin/env python3
"""Proves that nothing outside lib/backend/ knows which host is behind it.

The request was to be able to change servers later. An interface alone does not
deliver that: a `SupabaseBackend` imported directly from a widget, or a project
URL read in a settings screen, re-welds the app to the vendor one file at a
time, quietly, and nothing fails until the day somebody tries to move.

So the boundary is checked rather than remembered. Two rules:

  1. Only lib/backend/ may name a concrete backend or a vendor package.
  2. lib/backend/ may not import the app back — no widgets, no stores, no
     turn pipeline. A backend that reaches into the UI cannot be swapped
     without dragging the UI with it.

Run: python3 tool/scan_backend_boundary.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Both apps. v1 is frozen at the root and v2 is being built in app/, and the
# seam matters more in the one still being written — a scan that only watched
# the finished tree would be guarding the code least likely to break it.
#
# Written as a list rather than a parameter because it must not be possible to
# run this and have it silently check half of what there is. That is the same
# failure the conditional-import scanner had: it watched v1 only, and every
# "23 pairs clean" reported during the v2 rebuild was true of the wrong tree.
TREES = [tree for tree in (ROOT / "lib", ROOT / "app" / "lib") if tree.is_dir()]

# Things only lib/backend/ is allowed to mention.
VENDOR = [
    (re.compile(r"\bsupabase\b", re.IGNORECASE), "supabase"),
    (re.compile(r"\bSupabaseBackend\b"), "SupabaseBackend"),
    (re.compile(r"\bBackendConfig\b"), "BackendConfig"),
    (re.compile(r"\bNoBackend\b"), "NoBackend"),
]

# Directories lib/backend/ may not import from: it is a leaf, and stays one.
FORBIDDEN_INBOUND = ("features/", "core/", "providers/", "turn/", "data/stores/")

IMPORT = re.compile(r"""^\s*import\s+['"]([^'"]+)['"]""", re.MULTILINE)


def check(lib: pathlib.Path, problems: list[str]) -> int:
    """Both rules, for one app's `lib/`. Returns how many backend files it saw."""
    backend = lib / "backend"
    if not backend.is_dir():
        return 0

    # Rule 1 — the vendor stays inside the folder. `app.dart` is the one
    # exception: something has to choose an implementation, and doing it at the
    # composition root is the standard place. It may name them; nothing else may.
    allowed = {lib / "app.dart"}
    for path in sorted(lib.rglob("*.dart")):
        if backend in path.parents or path in allowed:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for pattern, label in VENDOR:
            if pattern.search(text):
                rel = path.relative_to(ROOT)
                problems.append(f"{rel} mentions '{label}' outside backend/")

    # Rule 2 — the folder does not import the app.
    for path in sorted(backend.rglob("*.dart")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for target in IMPORT.findall(text):
            resolved = (path.parent / target).resolve()
            try:
                rel_target = resolved.relative_to(lib).as_posix()
            except ValueError:
                continue  # a package: import, not a path into lib/
            if any(rel_target.startswith(d) for d in FORBIDDEN_INBOUND):
                rel = path.relative_to(ROOT)
                problems.append(f"{rel} imports '{target}' — backend/ is a leaf")

    return len(list(backend.rglob("*.dart")))


def main() -> int:
    problems: list[str] = []
    seen = {tree: check(tree, problems) for tree in TREES}

    if problems:
        print("Backend boundary violations:", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        print(
            "\nThe app talks to ShiftBackend and nothing else. Changing hosts "
            "must stay a new class in lib/backend/.",
            file=sys.stderr,
        )
        return 1

    # Named per tree rather than totalled. A single number cannot be read as
    # "and it looked at both", which is exactly the claim this needs to make.
    where = ", ".join(
        f"{tree.relative_to(ROOT).as_posix()}/backend: {count} file(s)"
        for tree, count in seen.items()
    )
    print(f"backend boundary intact ({where})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
