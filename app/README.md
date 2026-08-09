# SHIFT AI — v2

Chat, code, images, design, work and notes in one app, on six platforms.

This directory is **v2**, rebuilt from scratch. **v1 lives at the repository
root**, is frozen, and keeps building and deploying so there is always
something that runs. No feature work goes into v1.

## Why a rebuild rather than a restructure

v1 works, but it cannot be submitted to either mobile store, for structural
reasons rather than cosmetic ones: there is no iOS target at all, Android
release builds are signed with the debug key, the manifest declares
`REQUEST_INSTALL_PACKAGES`, and the self-updater downloads and installs an
APK — which Play's Device and Network Abuse policy prohibits outright. Three of
those are *removals*, and each is load-bearing in v1.

## The one idea to know

**Modes are workspaces, not routers.** Every mode can produce everything — ask
for a landing page in Notes and you get a landing page. A mode chooses the
*surface*: what is on screen, what is at hand, what the defaults are. The
engine behind all six is the same.

That is why Chat is the default and why it has to be able to answer anything.

## Layout

```
lib/
  core/design/    tokens — palette, metrics, typography, theme
  core/device/    device class (which is not the same question as window width)
  core/platform/  conditional-import shims
  shell/          the six-mode shell
```

## Running it

```sh
flutter pub get
flutter run -d linux            # or chrome, macos, windows, ios, android
```

The phone surface is otherwise unreachable from a desktop, so:

```sh
flutter run --dart-define=SHIFT_DEVICE_CLASS=phone
```

That override is permanent rather than a test hook — it is also the fastest way
to answer a support question about a layout somebody is seeing.

## The gate

Every wave ends green on all of this:

```sh
flutter analyze
flutter test
python3 tool/scan_conditional_imports.py
flutter build web --wasm --release --no-web-resources-cdn
flutter build linux --release
```

`--no-web-resources-cdn` is not optional. Without it the engine is fetched from
`gstatic.com` at runtime, which is a third-party request on first paint and a
blank app for anyone offline.

## Things that will bite you

**The viewport meta tag.** Flutter's web template still ships without one, in
3.44, a year after this cost v1 every phone laying out at ~980px and scaling
down. `web/index.html` has it and CI asserts it.

**Bundled fonts only.** CanvasKit renders text from bundled font bytes and does
not fall back to the browser's generic stacks — which is why `monospace` is
registered as a literal family name in `pubspec.yaml`.

**A `TextTheme` with gaps.** Every slot left undefined resolves to Material's
Roboto, which the web build then downloads from `fonts.gstatic.com`. The theme
merges onto the platform theme and forces the family, so no slot can escape.

**Fallback fonts.** `web/fonts/fallback/` is empty and must not stay that way
past N2 — see its README.

**Conditional imports.** The analyzer resolves only the default branch. Run the
scan before every build.

## What is verifiable here, and what is not

Linux and web are built and run in the development sandbox. **macOS, Windows,
iOS and Android are verified in CI as *built*, never as *installed and run*** —
there is no runner for them, and no amount of care changes that. Android has no
SDK locally either, so it is CI-only.

Signing is wired to secrets that may be absent. When they are, the Android
release build falls back to the debug key: installable for testing, and
rejected by Play. That is the intended failure — a local build that quietly
produced a Play-shaped artifact would be worse.
