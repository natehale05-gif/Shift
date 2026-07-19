{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load({
  config: {
    // Serve CanvasKit from this build's own bundle instead of the
    // gstatic.com CDN — more robust on networks that block that CDN, and
    // avoids depending on external infrastructure for a static GitHub Pages
    // deployment.
    canvasKitBaseUrl: "canvaskit/",
  },
});
