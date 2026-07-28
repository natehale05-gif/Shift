import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

/// Web: package:http's XHR-based BrowserClient buffers whole responses,
/// which breaks incremental SSE — fetch + ReadableStream doesn't.
http.Client createStreamingClient() => FetchClient(mode: RequestMode.cors);
