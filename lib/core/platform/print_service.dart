// Print an HTML document via the browser's print dialog (Save as PDF). Resolves
// to the web implementation in the browser and a no-op stub elsewhere.
export 'print_service_stub.dart'
    if (dart.library.html) 'print_service_web.dart';
