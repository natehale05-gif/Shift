# App icon source

Put the master icon here as **`app_icon.png`**, 1024×1024. Then, in one pass:

1. Uncomment `- assets/icon/app_icon.png` under `flutter: assets:` in
   `pubspec.yaml`. (It is commented out because declaring an asset that does not
   exist fails the build, and the file is not in the repo yet.)
2. Generate every platform's icons:

   ```bash
   dart run flutter_launcher_icons
   ```

That writes the Android mipmaps, the macOS `AppIcon.appiconset`, the Windows
`.ico`, and the web `icons/` + `favicon.png`. The generated files are committed,
so CI builds need no extra step.

## iOS home screen

`dart run flutter_launcher_icons` does **not** produce an iOS-correct icon for
"Add to Home Screen" — Safari ignores `manifest.json` and uses the
`apple-touch-icon` link, which needs an opaque, full-bleed, 180x180 image. Run:

```bash
python3 tool/make_apple_touch_icon.py
```

Then **bump the filename** in `web/index.html` (e.g. `-180.png` ->
`-180-v2.png`). iOS caches apple-touch-icons by URL and never revalidates, and
the service worker caches by URL as well, so reusing a path means both keep
serving the old icon no matter what the server returns.

## Notes

- **Linux** is not covered by the generator. `linux/runner/my_application.cc`
  loads this PNG from the bundle at startup to set the window and taskbar icon;
  it is a no-op while the asset is absent, so a missing file can never stop the
  app launching.
- **Android adaptive icons are deliberately off.** They need a second,
  transparent, glyph-only image with roughly 25% padding — without one, the
  launcher's circular mask crops a rounded-square icon at the corners. To enable
  them later, add `app_icon_foreground.png` here and put back
  `adaptive_icon_background` / `adaptive_icon_foreground` in the
  `flutter_launcher_icons` block.
- **`background_color`** in the web config is the PWA splash colour and is
  deliberately `#F5F4EF` to match the HTML boot splash in `web/index.html`, not
  the icon's own dark plate — otherwise an installed PWA flashes dark before the
  app's light background appears.
