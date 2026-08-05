/// Prepares an artifact's HTML for *preview*, without changing the artifact.
///
/// Everything here exists because a preview frame is not a browser tab, and a
/// page written for a browser tab misbehaves in one in ways that read as the
/// app being broken:
///
/// * **A link had nowhere to go.** A generated page's nav is full of
///   `href="/menu"` and `href="about.html"`. In a `srcdoc` frame those resolve
///   against the *app's* address, so clicking one replaced the preview with a
///   404 from the hosting — the page apparently destroying itself. A `<base
///   target="_blank">` sends them to a new tab instead, and the preview stays
///   where it was.
///
/// * **An image that never loads still takes up its space.** Models write
///   `<img src="https://images.example/hero.jpg">` for pages they cannot put
///   real pictures in. The layout reserves the space, nothing arrives, and the
///   page looks like it is showing a photograph that has failed to appear.
///   Saying so is better than leaving a gap that pretends.
///
/// Applied at render time and never stored: a download has to be the file the
/// model actually wrote, not this. That is also why it is a pure function on
/// its own — the transformation is testable without a browser, and there is
/// one place to look when a preview differs from the download.
library;

/// The marker that stops this being applied twice — to a page that already
/// went through it, or to one that happens to contain the same script.
const _marker = 'data-shift-preview';

String previewDocument(String html) {
  if (html.contains(_marker)) return html;

  final head = StringBuffer('<meta $_marker="1">');

  // Only when the page has not chosen its own. A page that sets `<base>` is
  // making a deliberate decision about how its links resolve, and overriding
  // it would break exactly the pages that were written most carefully.
  if (!RegExp(r'<base\b', caseSensitive: false).hasMatch(html)) {
    head.write('<base target="_blank">');
  }

  head.write(_imageFallback);

  final headOpen = RegExp(r'<head\b[^>]*>', caseSensitive: false);
  final match = headOpen.firstMatch(html);
  if (match != null) {
    return html.replaceRange(match.end, match.end, head.toString());
  }

  // No <head> — a fragment, or a page written without one. Prepending is
  // valid: the parser hoists these into the head it synthesises.
  return '$head$html';
}

/// Turns an image that did not load into something that says so.
///
/// `onerror` rather than a URL check, because whether a URL resolves is not
/// knowable from here — and a page whose images *do* load must be left alone.
/// The replacement keeps the element's own size so the layout does not jump.
const _imageFallback = '''
<style>
img[$_marker-failed] {
  background: repeating-linear-gradient(
    45deg, rgba(127,127,127,.10) 0 10px, rgba(127,127,127,.16) 10px 20px);
  border-radius: 8px;
  min-height: 120px;
  object-fit: contain;
  position: relative;
}
</style>
<script>
(function () {
  // A 1x1 transparent pixel, so the browser stops drawing its broken-image
  // icon over the placeholder underneath.
  var blank = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
  function mark(img) {
    if (img.hasAttribute('$_marker-failed')) return;
    img.setAttribute('$_marker-failed', '');
    img.setAttribute('title', 'Image unavailable');
    if (!img.alt) img.alt = 'Image unavailable';
    img.src = blank;
  }
  document.addEventListener('error', function (event) {
    var target = event.target;
    if (target && target.tagName === 'IMG') mark(target);
  }, true); // capture: error does not bubble.
})();
</script>
''';
