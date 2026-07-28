// Window-level file intake for the composer: pasted images and dropped files.
// Resolves to the web implementation in the browser and a no-op stub elsewhere
// (and in unit tests).
export 'file_intake_stub.dart'
    if (dart.library.html) 'file_intake_web.dart';
