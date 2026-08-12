#!/usr/bin/env bash
#
# What the deployed site actually serves, and where the README sends people.
#
# The second half is the one that was missing, and it is the one that mattered.
# This script was written to settle "I'm not seeing v2 on Pages" and it checked
# the site — correctly, and it passed — while the actual fault was that
# `README.md`'s "Try it in your browser" button pointed at v1. Three rounds
# went into a service worker, a wasm MIME type and a cached 404, and the one
# artifact standing between a person and the app was never checked at all.
#
# So: assert *which app* answers each URL, and assert that every link in the
# README goes where it claims. A check of the destination is not a check of the
# signpost.
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

readme="$(dirname "$0")/../README.md"
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

# Every probe reports what it saw, not merely whether it liked it.
#
# The first live run of this script passed in under a second and printed one
# line of success — indistinguishable, from the outside, from a script that
# silently did nothing. The observations are the record.
note() { printf '  %-46s %s\n' "$1" "$2"; }

# Which of the two builds answered. Both apps share a name, an icon and a
# splash screen, so this tag is the only thing that distinguishes them — and
# comparing each base href to its own path, which is what this used to do,
# stays true for *either* app at the root.
app_marker() {
  sed -n 's/.*name="shift-app" content="\([^"]*\)".*/\1/p' "$tmp/body" | head -1
}

# A README link, re-pointed at the site under test.
#
# In CI the site under test *is* the canonical URL, so this is the identity
# and the real link is fetched. Locally it turns the published address into
# the equivalent path on the replica — which is what makes this check runnable
# at all here, since this sandbox's proxy blocks *.github.io. The path is the
# part that goes wrong; the host has never been the problem.
against_site() {
  local rest
  rest=$(printf '%s' "$1" | sed -E 's#^https?://[^/]+/[^/]+/##')
  printf '%s%s' "$site" "$rest"
}

run_checks() {
  failures=()

  probe "$site"
  note "$site" "HTTP $status · $(app_marker)"
  [ "$status" = 200 ] \
    || failures+=("root: $site -> HTTP $status, want 200")
  [ "$(app_marker)" = 'v2' ] \
    || failures+=("root: $site serves '$(app_marker)', not v2 — this is the exact fault that had the user looking at the old app")
  grep -q "<base href=\"$base\"" "$tmp/body" \
    || failures+=("root: $site does not carry <base href=\"$base\">")

  probe "${site}v1/"
  note "${site}v1/" "HTTP $status · $(app_marker)"
  [ "$status" = 200 ] \
    || failures+=("v1: ${site}v1/ -> HTTP $status, want 200")
  [ "$(app_marker)" = 'v1' ] \
    || failures+=("v1: ${site}v1/ serves '$(app_marker)', not v1")

  probe "${site}flutter_bootstrap.js"
  note "${site}flutter_bootstrap.js" "HTTP $status · $ctype"
  [ "$status" = 200 ] \
    || failures+=("loader: HTTP $status, want 200")

  # Measured, not assumed: a wrong MIME here does not degrade to the JS build
  # shipped beside it. The loader throws on WebAssembly.compile and stops, and
  # the splash spins forever.
  probe "${site}main.dart.wasm"
  note "${site}main.dart.wasm" \
    "HTTP $status · $ctype · $(wc -c < "$tmp/body") bytes"
  [ "$status" = 200 ] \
    || failures+=("engine: ${site}main.dart.wasm -> HTTP $status, want 200")
  case "$ctype" in
    application/wasm*) ;;
    *) failures+=("engine: served as '$ctype', not application/wasm — the loader refuses it and the app never boots") ;;
  esac

  # The address v2 used to live at. It is in the README, in this repo's
  # history and in a browser history; it must lead somewhere.
  probe "${site}v2/"
  note "${site}v2/ (moved)" "HTTP $status"
  [ "$status" = 200 ] \
    || failures+=("the old v2 address -> HTTP $status; it should redirect, not 404")

  # Cache-busting suffix so a previously-cached 404 cannot answer this.
  probe "${site}no-such-path-$(date +%s)/"
  note "a path that does not exist" "HTTP $status · $ctype"
  [ "$status" = 404 ] \
    || failures+=("missing path: HTTP $status, want 404")
  # Quoted, because that is what a Flutter shell emits and prose about the tag
  # is not the tag. The unquoted form matched this repo's own 404 page comment.
  if grep -q '<base href="' "$tmp/body"; then
    failures+=("missing path: the 404 body is an application shell — a missing page is indistinguishable from a working one")
  fi

  # --- the signpost, not the destination -----------------------------------
  #
  # Every published link in the README has to resolve, and the one people
  # actually press has to serve the app it advertises.
  if [ -f "$readme" ]; then
    # The **first** site link in the document, whatever it is labelled.
    #
    # It used to grep for the literal phrase "Try it in your browser", which is
    # how this check spent three commits red while the site was perfectly
    # fine: the button was reworded to "Open it in your browser" and the grep
    # found nothing, so the check failed closed on its own wording. Failing
    # closed is the right direction and a check nobody can keep green is still
    # a check nobody reads.
    #
    # Position is the property that actually matters and it cannot be reworded
    # away: whichever link comes first is the one people press, and it has to
    # serve the current app. That is precisely what was wrong before — a v1
    # button above a v2 pointer in a blockquote.
    local primary
    primary=$(grep -o '\](https://natehale05-gif\.github\.io[^)]*)' "$readme" \
              | sed -E 's/.*\((.*)\)/\1/' | head -1)

    if [ -z "$primary" ]; then
      failures+=("README links to the site nowhere at all")
    else
      probe "$(against_site "$primary")"
      note "README's first link -> $primary" "HTTP $status · $(app_marker)"
      [ "$status" = 200 ] \
        || failures+=("README's first site link -> HTTP $status")
      [ "$(app_marker)" = 'v2' ] \
        || failures+=("README's first site link serves '$(app_marker)' — the link people press has to be the current app")
    fi

    while read -r url; do
      [ -n "$url" ] || continue
      probe "$(against_site "$url")"
      note "README link $url" "HTTP $status"
      [ "$status" = 200 ] \
        || failures+=("README links to $url, which answers HTTP $status")
    done < <(grep -o 'https://natehale05-gif\.github\.io[^)" ]*' "$readme" \
             | sort -u)
  fi

  [ ${#failures[@]} -eq 0 ]
}

while :; do
  if run_checks; then
    echo "$site serves v2, ${site}v1/ serves v1, and the README agrees."
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
