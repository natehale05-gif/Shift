# SHIFT AI

An intuitive app for shiftai.club that works like the Claude app but feels like
an Apple product. Talk to it like you would a person — it routes your request to
the right specialised studio automatically.

**[▶ Try it in your browser](https://natehale05-gif.github.io/Shift/)** — no
install, no key required. Demo mode simulates every studio.

## Download

[![macOS](https://img.shields.io/badge/macOS-Install-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/natehale05-gif/Shift/releases/latest/download/SHIFT-AI-macos.dmg)
[![Windows](https://img.shields.io/badge/Windows-Install-0078D4?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/natehale05-gif/Shift/releases/latest/download/SHIFT-AI-windows-setup.exe)
[![Linux](https://img.shields.io/badge/Linux-Install-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://github.com/natehale05-gif/Shift/releases/latest/download/SHIFT-AI-linux-amd64.deb)
[![Android](https://img.shields.io/badge/Android-Install-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/natehale05-gif/Shift/releases/latest/download/SHIFT-AI-android.apk)

Each button is a real installer, not an archive to unpack:

| Platform | What you get | How to install |
|---|---|---|
| **macOS** | `.dmg` disk image | Open it, drag **SHIFT AI** into Applications |
| **Windows** | `.exe` setup | Run it — Start Menu entry, desktop shortcut, uninstaller |
| **Linux** | `.deb` package | `sudo dpkg -i SHIFT-AI-linux-amd64.deb`, then launch it from your apps menu |
| **Android** | `.apk` | Tap it and confirm the install |

Every button points at `releases/latest`, so it always fetches the newest build.
All builds are on the [Releases page](https://github.com/natehale05-gif/Shift/releases).

**Portable builds.** `SHIFT-AI-windows.zip` and `SHIFT-AI-linux-x64.tar.gz` are
also published for anyone who would rather not install anything — extract and
run. On Linux the tarball is additionally the *self-updating* copy: a `.deb`
installs into root-owned `/opt`, so that copy cannot replace itself and the app
says so and links you back here instead of failing an update halfway.

**You only download once.** The app checks for new releases daily and installs
them itself — silently on Linux and Windows, applied the next time you open it.
On macOS and Android it downloads the update and hands it to the OS installer,
which asks you to confirm; unsigned software cannot install without that prompt.
Turn it off in **Settings → Updates**. The browser version updates on reload.

### First launch

These builds are **unsigned** — code-signing certificates cost money and this
project does not have them. Your OS will object exactly once:

| | |
|---|---|
| **macOS** | Right-click the app → **Open** → **Open**. If it claims the app is "damaged": `xattr -dr com.apple.quarantine "/Applications/SHIFT AI.app"` |
| **Windows** | SmartScreen shows a blue box → **More info** → **Run anyway** |
| **Android** | Allow installs from unknown sources for your file manager when prompted |
| **Linux** | No warning — `dpkg` does not check signatures for a local file |

The Windows installer installs per-user, into
`%LOCALAPPDATA%\Programs\SHIFT AI`, which is what lets the app update itself
later. You can choose an all-users install instead; the app then detects that it
cannot write to its own directory and points you back to the Releases page for
updates rather than failing one halfway through.

### What differs from the browser version

Chats, projects, artifacts, downloads and bring-your-own-key providers all work
the same, and **chats persist between launches**. Three things differ, because
they are browser APIs:

- **Dictation, live voice, paste/drag-drop intake and printing** are
  browser-only. The attach button works everywhere.
- **Artifact previews** open in your default browser rather than inline — the
  desktop app embeds no browser engine. The Code tab shows the source in-app.
- **Generated audio** opens in your system audio player rather than playing
  inline.

In exchange, the desktop and Android builds keep your chats between launches and
update themselves.

## Bring your own key

The app ships in demo mode: every studio responds with simulated output, so
nothing is hidden behind a signup. Add a key in **Settings → API keys** and the
same requests run against the real provider — Anthropic, Google Gemini, OpenAI,
Groq, Mistral, OpenRouter, Flux or Heygen. Keys are stored on your own device
and calls go direct to the provider.

## Building from source

```bash
flutter pub get
flutter test
flutter run -d chrome     # or: -d linux, -d macos, -d windows, -d <android device>
```

Linux desktop builds additionally need `libgtk-3-dev ninja-build clang cmake
pkg-config`.
