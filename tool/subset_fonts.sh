#!/usr/bin/env bash
# Regenerate the bundled font subsets.
#
# Why: CanvasKit renders text from bundled font bytes only, so every glyph the
# app can draw has to ship. The upstream faces are full Unicode TTFs (~2.2 MB
# total) and all of it downloads on first visit — a real cost on a phone over
# mobile data. Subsetting to the ranges this app actually renders cuts that by
# roughly half with no visible change.
#
# Originals live in assets/fonts/src/ (NOT bundled — pubspec.yaml lists only the
# subset files in assets/fonts/). Re-run this after replacing an original.
#
#   pip install fonttools && tool/subset_fonts.sh
#
# Scripts beyond these ranges (CJK, Arabic, …) are not in these faces to begin
# with; CanvasKit falls back to its own font for those, exactly as before.
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="assets/fonts/src"
OUT="assets/fonts"

if [ ! -d "$SRC" ]; then
  echo "error: $SRC not found — originals must be there to subset from." >&2
  exit 1
fi

# Basic+Latin-1, Latin Extended-A/B, Latin Extended Additional, General
# Punctuation (em dash, curly quotes, ellipsis — used heavily in UI copy),
# currency, letterlike, arrows, math, box drawing, geometric shapes (bullets),
# and the fi/fl ligatures.
LATIN="U+0000-00FF,U+0100-024F,U+1E00-1EFF,U+2000-206F,U+20A0-20CF"
LATIN="$LATIN,U+2100-214F,U+2190-21FF,U+2200-22FF,U+2500-257F,U+25A0-25FF,U+FB00-FB06"

# Greek + Cyrillic, kept only for the UI body face: the Translate studio can put
# those scripts into ordinary chat text.
GREEK_CYRILLIC="U+0370-03FF,U+0400-04FF"

# Keep kerning and the ligature/mark features so shaping quality is unchanged.
FEATURES="kern,liga,clig,calt,ccmp,mark,mkmk"

subset() { # $1 = file stem, $2 = unicode ranges
  python3 -m fontTools.subset "$SRC/$1.ttf" \
    --unicodes="$2" \
    --layout-features="$FEATURES" \
    --drop-tables+=DSIG \
    --output-file="$OUT/$1.ttf"
  printf '  %-28s %5s KB -> %4s KB\n' "$1" \
    "$(( $(stat -c%s "$SRC/$1.ttf") / 1024 ))" \
    "$(( $(stat -c%s "$OUT/$1.ttf") / 1024 ))"
}

echo "Subsetting fonts:"
# Body/UI face — needs Greek + Cyrillic for translated chat text.
for w in Regular Medium SemiBold Bold; do
  subset "Inter-$w" "$LATIN,$GREEK_CYRILLIC"
done
# Code face — code is Latin.
for w in Regular Medium Bold; do
  subset "JetBrainsMono-$w" "$LATIN"
done
# Display face — wordmark, greeting, headings. Latin only.
for w in Regular SemiBold Bold; do
  subset "SourceSerif4-$w" "$LATIN"
done

echo
echo "Total bundled: $(du -ch "$OUT"/*.ttf | tail -1 | cut -f1)"
