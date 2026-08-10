import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Whether this device can reach anything at all.
///
/// The question exists because a browser can refuse a cross-site request
/// *before it leaves the device* — a content blocker, a private-browsing
/// shield, or a response the provider sent without the CORS headers that would
/// let the page read it. From inside Dart all three are identical to being
/// offline: no status, no body, just a bare transport error. That ambiguity has
/// now cost two debugging sessions in this project, in two different layers.
///
/// One cheap request to an origin that is *known* to be permitted separates
/// them. If the app's own origin answers while the provider request did not,
/// the network is fine and that specific request was refused.
enum Reach {
  /// Something answered, so the device has a working connection.
  up,

  /// Nothing answered. The device is offline or the whole origin is
  /// unreachable.
  down,

  /// The question does not apply here. Off-web there is no browser to block
  /// anything, so a transport failure really is a transport failure and
  /// claiming otherwise would be inventing a diagnosis.
  unknown,
}

/// Asks the app's own origin whether it is reachable.
///
/// [isBrowser] and [client] are injected so both arms are testable; neither is
/// passed in the app. **`kIsWeb` rather than `identical(0, 0.0)`** — the old
/// trick for detecting a JS runtime is *false* under dart2wasm, which is what
/// this build compiles to, so it would report every browser as off-web.
Future<Reach> probeReach({
  http.Client? client,
  bool? isBrowser,
  Duration timeout = const Duration(seconds: 4),
}) async {
  if (!(isBrowser ?? kIsWeb)) return Reach.unknown;

  final owned = client == null;
  final c = client ?? http.Client();
  try {
    // Same-origin, so no preflight and no CORS decision to lose to. The
    // cache-buster matters: `flutter_bootstrap.js` is exactly the kind of file
    // an HTTP cache holds, and a cached 200 while offline would report `up`
    // and blame a content blocker for a flight-mode switch.
    final uri = Uri.base.resolve('flutter_bootstrap.js').replace(
      queryParameters: {'reach': '${DateTime.now().millisecondsSinceEpoch}'},
    );
    final response = await c.get(uri).timeout(timeout);

    // Any answer at all proves the connection. Even a 404 would — the server
    // spoke. A 5xx is the one case where the origin is up but broken, and
    // treating that as `down` keeps the app from claiming a content blocker is
    // at fault when the host is having an outage.
    return response.statusCode >= 500 ? Reach.down : Reach.up;
  } catch (_) {
    return Reach.down;
  } finally {
    if (owned) c.close();
  }
}
