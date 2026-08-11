/// Where bytes live.
///
/// [KvStore] is a string map read whole and written whole, which is fine for
/// keys and preferences and wrong for an image. Two reasons, and either alone
/// would settle it: a megabyte of base64 in that map is rewritten to disk on
/// every unrelated save, and on the web `localStorage` gives an origin about
/// 5 MB in total — three pictures and the app starts throwing.
///
/// So bytes get their own store: files off-web, IndexedDB in the browser. The
/// index that says *what* the bytes are stays in the KV, because it is small
/// and the gallery has to read all of it at once.
///
/// **The conditional key is `dart.library.js_interop`, not `dart.library.html`.**
/// The latter is false under dart2wasm, which is what v2 builds with, so a pair
/// keyed on it silently takes the wrong arm on the web with no error at all.
library;

export 'asset_store_io.dart'
    if (dart.library.js_interop) 'asset_store_web.dart';
