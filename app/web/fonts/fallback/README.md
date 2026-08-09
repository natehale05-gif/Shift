# Fallback fonts

Empty on purpose, and it must not stay that way past N2.

## What this directory is

Flutter's web engine downloads a fallback font when it lays out a code point
that none of the bundled faces covers — emoji, CJK, Arabic, Devanagari. By
default it fetches those from `fonts.gstatic.com`.

`web/flutter_bootstrap.js` repoints that at this directory, because a
third-party request on a cold load is three separate problems: a disclosure on
the App Store privacy questionnaire and Play's Data Safety form, a hard
dependency on Google being reachable, and a missing glyph for anyone offline.

## Why empty is fine right now

N0's app renders a fixed set of Latin strings, and every character in them is
in Inter, Source Serif 4 or JetBrains Mono. Confirmed rather than assumed: the
build was measured with the gstatic request blocked at the network layer and
rendered correctly, because the engine treats a failed fallback download as a
non-fatal miss rather than an error.

## Why it stops being fine

**N2 adds a composer that accepts arbitrary text.** The first person to type an
emoji, or anything in a non-Latin script, gets tofu boxes — and they will
reasonably read that as the app being broken rather than as a font boundary.

## What has to land here before N2 ships

At minimum:

- **Noto Color Emoji** — the common case by a wide margin.
- **Noto Sans** covering the scripts we intend to support.

Named so the engine can find them by the same filenames it would have requested
from `fonts.gstatic.com`. The engine's expected file list comes from its own
fallback font manifest; generate it by letting a build request the fonts from
the default URL once and recording what it asks for, rather than guessing the
names.

The alternative — reverting to the gstatic default — is a legitimate choice,
but it is a choice about user privacy and offline behaviour and should be made
deliberately, not by leaving this directory empty and forgetting.
