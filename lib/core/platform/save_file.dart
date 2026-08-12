/// Putting bytes somewhere the person can find them again.
///
/// A generated picture that cannot leave the app is a picture you have to
/// screenshot, so this is not a nicety — it is the difference between a
/// deliverable and a preview.
///
/// The two platforms disagree about what "save" even means: off-web it is a
/// dialog and a path, in a browser it is a download the user never chooses a
/// location for. So the shared contract is deliberately weak — it reports
/// whether the bytes went, not where — because a path is a thing only one arm
/// has and inventing one for the other would be a lie a caller could print.
///
/// **The conditional key is `dart.library.js_interop`, not `dart.library.html`.**
/// The latter is false under dart2wasm, which is what v2 builds with.
library;

export 'save_file_io.dart' if (dart.library.js_interop) 'save_file_web.dart';
