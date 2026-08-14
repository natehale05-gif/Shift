/// The smallest thing that remembers something between launches.
///
/// Deliberately a string map and not a document store. Conversations will need
/// one — indexed, queryable, holding attachments — and picking that dependency
/// now would be guessing at a shape N2 has not settled. This holds keys, a
/// session and preferences, which are all short strings.
///
/// **The conditional key is `dart.library.js_interop`, not `dart.library.html`.**
/// The latter is false under dart2wasm, which is what v2 builds with, so a pair
/// keyed on it silently takes the wrong arm on the web with no error at all.
/// `tool/scan_conditional_imports.py` checks both arms declare the same names.
library;

export 'kv_store_io.dart' if (dart.library.js_interop) 'kv_store_web.dart';
