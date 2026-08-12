#!/usr/bin/env python3
"""Opens the generated documents with readers that are not ours.

Why this exists as a separate step rather than a Dart test: every assertion a
Dart test can make about a `.docx` is an assertion about the bytes *we* wrote,
checked by the code that wrote them. That catches a dropped block; it cannot
catch a file Word refuses. python-docx, openpyxl and python-pptx are
independent implementations of the same formats, so what they report is
evidence rather than agreement.

It found the bug that made this worth writing: a `docProps/core.xml` that
nothing pointed at, so every document was called "Word Document" and every part
of it was correct.

    dart run tool/gen_docs.dart build/documents
    pip install python-docx openpyxl python-pptx
    python3 tool/check_documents.py build/documents

Not in CI: the readers are a Python dependency and the suite is Dart. Run it
whenever `lib/documents/` changes — which is the moment it can start lying.
"""
import sys
from pathlib import Path

FAILURES = []


def check(label, condition, detail=""):
    mark = "ok  " if condition else "FAIL"
    print(f"  {mark} {label}{'' if condition else f'  <- {detail}'}")
    if not condition:
        FAILURES.append(label)


def check_docx(path):
    import docx

    print(f"{path.name}")
    d = docx.Document(path)
    styles = [p.style.name for p in d.paragraphs]
    text = "\n".join(p.text for p in d.paragraphs)

    check("opens", True)
    check("title is the document's own, not a default",
          d.core_properties.title not in (None, "", "Word Document"),
          repr(d.core_properties.title))
    check("headings are real headings", "Heading 1" in styles, styles)
    check("bullets are a list style", "List Bullet" in styles, styles)
    check("numbers are a list style", "List Number" in styles, styles)
    check("a quote is a quote", "Quote" in styles, styles)
    check("bold survived",
          any(r.bold for p in d.paragraphs for r in p.runs))
    check("italic survived",
          any(r.italic for p in d.paragraphs for r in p.runs))
    # The characters most likely to be emitted raw and corrupt the part.
    check("punctuation survived", "&" in text and '"' in text and "'" in text)
    check("code kept its line break", "make publish" in text)


def check_xlsx(path):
    import warnings

    import openpyxl

    print(f"{path.name}")
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        wb = openpyxl.load_workbook(path)
    ws = wb.active
    rows = [[c.value for c in row] for row in ws.iter_rows()]

    check("opens with no warnings", True)
    check("sheet is named after the file", ws.title == "Regions", ws.title)
    check("header is frozen", ws.freeze_panes == "A2", ws.freeze_panes)
    check("header is bold", all(c.font.bold for c in next(ws.iter_rows())))
    # The whole reason to want a spreadsheet: text sums to zero and looks the
    # same until somebody tries.
    numbers = [r[1] for r in rows[1:] if isinstance(r[1], (int, float))]
    check("figures are numbers", len(numbers) == 4, numbers)
    check("they sum", sum(numbers[:3]) == 1149250, numbers)
    check("a quoted comma stayed one cell",
          rows[1][3] == "Opened in August, ramping", rows[1][3])
    check("a doubled quote came back as one",
          rows[3][3] == 'One large account said "maybe"', rows[3][3])


def check_pptx(path):
    from pptx import Presentation

    print(f"{path.name}")
    p = Presentation(path)
    slides = [
        [sh.text_frame.text for sh in s.shapes if sh.has_text_frame]
        for s in p.slides
    ]

    check("opens", True)
    check("title is the first slide's",
          p.core_properties.title == "Q3 in three minutes",
          p.core_properties.title)
    check("a heading and a rule both split", len(slides) == 4, len(slides))
    check("prose under a heading was kept",
          "Where the quarter landed" in slides[0][1], slides[0])
    check("bullets are on the slide", "Churn flat at 2.1%" in slides[1][1])
    check("emphasis was flattened, not shown",
          not any("**" in "".join(s) for s in slides))
    check("punctuation survived", '"detail"' in slides[3][1], slides[3])


def main():
    directory = Path(sys.argv[1] if len(sys.argv) > 1 else "build/documents")
    checks = {
        "brief.docx": check_docx,
        "regions.xlsx": check_xlsx,
        "deck.pptx": check_pptx,
    }
    for name, fn in checks.items():
        path = directory / name
        if not path.exists():
            FAILURES.append(f"{name} is missing — run tool/gen_docs.dart first")
            print(f"{name}\n  FAIL missing")
            continue
        fn(path)

    print()
    if FAILURES:
        print(f"{len(FAILURES)} failed")
        return 1
    print("all documents opened")
    return 0


if __name__ == "__main__":
    sys.exit(main())
