import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

/// Browsers: `package:http`'s default client is XHR-backed and buffers the
/// entire response before yielding any of it, which turns a streamed reply
/// into one lump at the end. `fetch` with a `ReadableStream` does not.
http.Client createStreamingClient() => FetchClient(mode: RequestMode.cors);

/// See the doc on the stub's copy: this exists so a web test can prove which
/// arm it got, since choosing wrong raises nothing.
const String streamingClientKind = 'fetch';
