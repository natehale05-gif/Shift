# SHIFT AI

Chat, code, images, design, work and notes in one app, on six platforms.

**[▶ Open it in your browser](https://natehale05-gif.github.io/Shift/)** — no
install; an account is required, and creating one takes a moment.

## Download it

| Platform | Get | |
|---|---|---|
| **macOS** | [`SHIFT-AI-macos.dmg`](https://github.com/natehale05-gif/Shift/releases/latest/download/SHIFT-AI-macos.dmg) | open it, drag the app across |
| **Windows** | [`SHIFT-AI-windows-setup.exe`](https://github.com/natehale05-gif/Shift/releases/latest/download/SHIFT-AI-windows-setup.exe) | installer, Start Menu entry, uninstaller |
| **Linux** | [`SHIFT-AI-linux-amd64.deb`](https://github.com/natehale05-gif/Shift/releases/latest/download/SHIFT-AI-linux-amd64.deb) | `sudo dpkg -i …`, then find it in your apps |
| **Android** | [`SHIFT-AI-android.apk`](https://github.com/natehale05-gif/Shift/releases/latest/download/SHIFT-AI-android.apk) | tap it and confirm |

Portable builds — [Windows `.zip`](https://github.com/natehale05-gif/Shift/releases/latest/download/SHIFT-AI-windows.zip)
and [Linux `.tar.gz`](https://github.com/natehale05-gif/Shift/releases/latest/download/SHIFT-AI-linux-x64.tar.gz) —
extract anywhere. On Linux the tarball is the **self-updating** one: a `.deb`
installs into root-owned `/opt`, so that copy cannot replace itself and says so
rather than failing an update halfway through.

**Desktop keeps itself current.** It checks daily, downloads in the background
and applies at the next launch — never quitting out from under you mid-sentence.
macOS asks once, because replacing unsigned software re-triggers Gatekeeper
whatever the app does.

**Android tells you and stops there**, on purpose: installing an APK from
inside the app needs a permission Google Play prohibits, and keeping it out is
what leaves Play open later.

Every build is unsigned, so each OS objects once — the release notes say
exactly how for each.

## Why this was rebuilt rather than restructured

There used to be a previous app at this path, and it has been deleted. It
worked, and it could not be submitted to either mobile store for structural
rather than cosmetic reasons: no iOS target at all, Android release builds
signed with the debug key, `REQUEST_INSTALL_PACKAGES` in the manifest, and a
self-updater that downloaded and installed an APK — which Play's Device and
Network Abuse policy prohibits outright. Three of those were *removals*, and
each was load-bearing in the old app, so unpicking them was most of a rewrite
done in the least pleasant order.

Its history is still in this repository; nothing about it is still built,
deployed or served.

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
3.44, a year after this cost the previous app every phone laying out at
~980px and scaling down. `web/index.html` has it and CI asserts it.

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
