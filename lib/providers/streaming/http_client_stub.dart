import 'package:http/http.dart' as http;

/// VM (test) target: the default IO client already streams responses.
http.Client createStreamingClient() => http.Client();
