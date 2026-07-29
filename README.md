# SHIFT AI

An intuitive app for shiftai.club that works like the Claude app but feels like
an Apple product. Talk to it like you would a person — it routes your request to
the right specialised studio automatically.

**[▶ Try it in your browser](https://natehale05-gif.github.io/Shift/)** — no
install, no key required. Demo mode simulates every studio.

## Download

[![macOS](https://img.shields.io/badge/macOS-Download-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/natehale05-gif/Shift/releases/latest/download/SHIFT-AI-macos.dmg)
[![Windows](https://img.shields.io/badge/Windows-Download-0078D4?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/natehale05-gif/Shift/releases/latest/download/SHIFT-AI-windows.zip)
[![Linux](https://img.shields.io/badge/Linux-Download-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://github.com/natehale05-gif/Shift/releases/latest/download/SHIFT-AI-linux-x64.tar.gz)
[![Android](https://img.shields.io/badge/Android-Download-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/natehale05-gif/Shift/releases/latest/download/SHIFT-AI-android.apk)

Every button points at `releases/latest`, so it always fetches the newest build.
All builds are on the [Releases page](https://github.com/natehale05-gif/Shift/releases).

### First launch

These builds are **unsigned** — code-signing certificates cost money and this
project does not have them. Your OS will object exactly once:

| | |
|---|---|
| **macOS** | Right-click the app → **Open** → **Open**. If it claims the app is "damaged": `xattr -dr com.apple.quarantine "/Applications/SHIFT AI.app"` |
| **Windows** | SmartScreen shows a blue box → **More info** → **Run anyway** |
| **Android** | Allow installs from unknown sources for your file manager when prompted |
| **Linux** | `tar -xzf SHIFT-AI-linux-x64.tar.gz && ./shift_ai` |

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
