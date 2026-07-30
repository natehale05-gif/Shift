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
LIB = ROOT / "lib"
BACKEND = LIB / "backend"

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


def main() -> int:
    problems: list[str] = []

    # Rule 1 — the vendor stays inside the folder. lib/app.dart is the one
    # exception: something has to choose an implementation, and doing it at the
    # composition root is the standard place. It may name them; nothing else may.
    allowed = {LIB / "app.dart"}
    for path in sorted(LIB.rglob("*.dart")):
        if BACKEND in path.parents or path in allowed:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for pattern, label in VENDOR:
            if pattern.search(text):
                rel = path.relative_to(ROOT)
                problems.append(f"{rel} mentions '{label}' outside lib/backend/")

    # Rule 2 — the folder does not import the app.
    for path in sorted(BACKEND.rglob("*.dart")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for target in IMPORT.findall(text):
            resolved = (path.parent / target).resolve()
            try:
                rel_target = resolved.relative_to(LIB).as_posix()
            except ValueError:
                continue  # a package: import, not a path into lib/
            if any(rel_target.startswith(d) for d in FORBIDDEN_INBOUND):
                rel = path.relative_to(ROOT)
                problems.append(f"{rel} imports '{target}' — backend/ is a leaf")

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

    files = len(list(BACKEND.rglob("*.dart")))
    print(f"backend boundary intact ({files} file(s) in lib/backend/)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
