import 'package:http/http.dart' as http;

/// Everywhere that is not a browser: the IO client already streams a response
/// body incrementally, so there is nothing to add.
http.Client createStreamingClient() => http.Client();

/// Which implementation this build got.
///
/// Not diagnostics — a guard. The web and non-web arms of this pair differ in
/// a way that produces **no error when it is wrong**: pick the IO arm in a
/// browser and `http.Client()` resolves to the XHR-backed `BrowserClient`,
/// which buffers the whole response and hands it over at the end. Streaming
/// silently stops being streaming, and the only symptom is that replies appear
/// all at once — which reads as a slow model.
///
/// A test asserts this is `fetch` in a web build, because nothing else can.
const String streamingClientKind = 'io';
