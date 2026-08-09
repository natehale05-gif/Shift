#!/usr/bin/env bash
#
# What the deployed site actually serves — asserted from a machine that can
# reach it.
#
# Every check before this one verified the *artifact*: that the bytes uploaded
# contained two apps with the right base hrefs. All of them passed while the
# reported symptom — "/Shift/v2/ shows the old app" — was live. They could not
# see the published site, because this sandbox's proxy blocks *.github.io, and
# that was allowed to stand as "unverifiable" when the CI runner has no such
# restriction and was simply never asked.
#
# The last check is the one that matters most and is the least obvious: a
# missing path must come back *looking* missing. The site's 404 page used to be
# a copy of v1's index.html, so every wrong URL under /Shift/ answered with v1
# and booted it. A 404 wearing a working app's face is indistinguishable from
# the app being at that URL.
#
# Usage:
#   tool/verify_site.sh https://natehale05-gif.github.io/Shift/
#   VERIFY_TIMEOUT=0 tool/verify_site.sh http://127.0.0.1:8000/
#
# VERIFY_TIMEOUT (default 120) is how long to keep retrying: GitHub Pages is
# eventually consistent, so a fresh deploy can 404 for a few seconds and this
# should not race the CDN. Set it to 0 to fail on the first pass, which is what
# a local run against a fixed tree wants.
set -uo pipefail

site="${1:-}"
if [ -z "$site" ]; then
  echo "usage: $0 <site url, e.g. https://host/Shift/>" >&2
  exit 2
fi
case "$site" in
  */) ;;
  *) site="$site/" ;;
esac

# The path the site is served from, which is what `<base href>` must equal.
# Derived from the URL rather than hardcoded, so a local tree served at / can
# be checked with the same script that checks /Shift/.
base="/$(printf '%s' "$site" | sed -E 's#^[a-z]+://[^/]+/##')"

retry="${VERIFY_RETRY:-10}"
deadline=$(( $(date +%s) + ${VERIFY_TIMEOUT:-120} ))

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

status=000
ctype='-'

probe() {
  local out
  out=$(curl -sS -L --max-time 30 -o "$tmp/body" \
          -w '%{http_code} %{content_type}' "$1" 2>>"$tmp/curl.err")
  status=${out%% *}
  ctype=${out#* }
  [ -n "$status" ] || status=000
}

run_checks() {
  failures=()

  probe "$site"
  [ "$status" = 200 ] \
    || failures+=("v1: $site -> HTTP $status, want 200")
  grep -q "<base href=\"$base\"" "$tmp/body" \
    || failures+=("v1: $site does not carry <base href=\"$base\">")

  # The check that was failing when this script was written. If /v2/ is absent
  # from the served tree, this is where it shows up — and with an honest 404
  # page it shows up as a 404 rather than as v1 booting.
  probe "${site}v2/"
  [ "$status" = 200 ] \
    || failures+=("v2: ${site}v2/ -> HTTP $status, want 200")
  grep -q "<base href=\"${base}v2/\"" "$tmp/body" \
    || failures+=("v2: ${site}v2/ answered with something that is not v2")

  probe "${site}v2/flutter_bootstrap.js"
  [ "$status" = 200 ] \
    || failures+=("v2 loader: ${site}v2/flutter_bootstrap.js -> HTTP $status, want 200")

  # Measured, not assumed: a wrong MIME here does not degrade to the JS build
  # shipped beside it. The loader throws on WebAssembly.compile and stops, and
  # the splash spins forever.
  probe "${site}v2/main.dart.wasm"
  [ "$status" = 200 ] \
    || failures+=("v2 engine: ${site}v2/main.dart.wasm -> HTTP $status, want 200")
  case "$ctype" in
    application/wasm*) ;;
    *) failures+=("v2 engine: served as '$ctype', not application/wasm — the loader refuses it and the app never boots") ;;
  esac

  # Cache-busting suffix so a previously-cached 404 cannot answer this.
  probe "${site}no-such-path-$(date +%s)/"
  [ "$status" = 404 ] \
    || failures+=("missing path: HTTP $status, want 404")
  # Quoted, because that is what a Flutter shell emits and prose about the tag
  # is not the tag. The unquoted form matched this repo's own 404 page comment.
  if grep -q '<base href="' "$tmp/body"; then
    failures+=("missing path: the 404 body is an application shell — a missing page is indistinguishable from a working one")
  fi

  [ ${#failures[@]} -eq 0 ]
}

while :; do
  if run_checks; then
    echo "$site and ${site}v2/ are both what they claim to be."
    exit 0
  fi
  now=$(date +%s)
  [ "$now" -lt "$deadline" ] || break
  echo "${#failures[@]} failing, retrying in ${retry}s (Pages is eventually consistent)"
  sleep "$retry"
done

for f in "${failures[@]}"; do
  echo "::error::$f"
  echo "$f" >&2
done
exit 1
