import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shift/providers/streaming/reachability.dart';

/// The probe that separates "the network is down" from "this request was
/// refused". It is one cheap same-origin request, and every decision it makes
/// is one someone will read as a diagnosis, so each is pinned.
void main() {
  test('off-web the question does not apply', () async {
    // There is no browser on a desktop build to block anything, so a transport
    // failure really is a transport failure. Answering `up` here would invent
    // a content blocker that cannot exist.
    expect(await probeReach(isBrowser: false), Reach.unknown);
  });

  test('an answer of any kind means the connection works', () async {
    for (final status in [200, 304, 404]) {
      expect(
        await probeReach(
            isBrowser: true, client: _FakeClient(() async => status)),
        Reach.up,
        reason: 'a $status is the server speaking, which is the whole question',
      );
    }
  });

  test('a server error is not proof the connection works', () async {
    // The origin is up but broken. Reporting `up` would blame a content
    // blocker for the host having an outage.
    expect(
      await probeReach(isBrowser: true, client: _FakeClient(() async => 503)),
      Reach.down,
    );
  });

  test('a refused probe is offline', () async {
    expect(
      await probeReach(
        isBrowser: true,
        client: _FakeClient(() async => throw http.ClientException('nope')),
      ),
      Reach.down,
    );
  });

  test('a hung probe does not hang the failure message', () async {
    // This runs *after* something already failed, so a person is waiting on it.
    expect(
      await probeReach(
        isBrowser: true,
        timeout: const Duration(milliseconds: 50),
        client: _FakeClient(() async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return 200;
        }),
      ),
      Reach.down,
    );
  });

  test('it defeats the cache rather than trusting it', () async {
    // A cached `flutter_bootstrap.js` answers 200 with the device in flight
    // mode, which would report `up` and blame a content blocker for a switch
    // the user flipped themselves.
    Uri? asked;
    await probeReach(
      isBrowser: true,
      client: _FakeClient(() async => 200, onUri: (uri) => asked = uri),
    );
    expect(asked!.queryParameters, contains('reach'));
  });
}

class _FakeClient extends http.BaseClient {
  final Future<int> Function() status;
  final void Function(Uri)? onUri;

  _FakeClient(this.status, {this.onUri});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    onUri?.call(request.url);
    return http.StreamedResponse(
      Stream.value(utf8.encode('')),
      await status(),
    );
  }
}
