import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shift_ai/core/update/update_check.dart';

String _releaseJson({
  String tag = 'v0.1.1',
  List<Map<String, dynamic>> assets = const [],
}) =>
    jsonEncode({
      'tag_name': tag,
      'html_url': 'https://github.com/natehale05-gif/Shift/releases/tag/$tag',
      'assets': assets,
    });

Map<String, dynamic> _asset(String name, {int size = 1024}) => {
      'name': name,
      'browser_download_url': 'https://example.test/$name',
      'size': size,
    };

void main() {
  UpdateCheck check(http.Client Function() factory) =>
      UpdateCheck(clientFactory: factory);

  test('reads the tag, page and assets off a release', () async {
    final mock = MockClient((request) async {
      expect(request.url.path, '/repos/natehale05-gif/Shift/releases/latest');
      // GitHub answers an unidentified client with a 403.
      expect(request.headers['User-Agent'], isNotEmpty);
      return http.Response(
        _releaseJson(assets: [
          _asset('SHIFT-AI-linux-x64.tar.gz', size: 4242),
          _asset('SHIFT-AI-android.apk'),
        ]),
        200,
      );
    });

    final release = await check(() => mock).fetchLatest();

    expect(release, isNotNull);
    expect(release!.tag, 'v0.1.1');
    expect(release.pageUrl, contains('releases/tag/v0.1.1'));
    expect(release.assets, hasLength(2));
    expect(release.assets.first.name, 'SHIFT-AI-linux-x64.tar.gz');
    expect(release.assets.first.size, 4242);
    expect(release.assets.first.downloadUrl, startsWith('https://'));
  });

  test('a 404 is null, not a throw', () async {
    // Literally the repository's state before the first release is cut, so
    // this is the path every early launch takes.
    final mock = MockClient((_) async => http.Response('{"message":"Not Found"}', 404));
    expect(await check(() => mock).fetchLatest(), isNull);
  });

  test('rate limiting is null', () async {
    final mock = MockClient((_) async => http.Response('{"message":"rate limit"}', 403));
    expect(await check(() => mock).fetchLatest(), isNull);
  });

  test('a network failure is null, not a throw', () async {
    final mock = MockClient((_) async => throw const SocketExceptionStub());
    expect(await check(() => mock).fetchLatest(), isNull);
  });

  test('malformed JSON is null', () async {
    final mock = MockClient((_) async => http.Response('not json at all', 200));
    expect(await check(() => mock).fetchLatest(), isNull);
  });

  test('a release with no tag is null', () async {
    final mock = MockClient(
        (_) async => http.Response(jsonEncode({'html_url': 'x'}), 200));
    expect(await check(() => mock).fetchLatest(), isNull);
  });

  test('malformed assets are skipped, not fatal', () async {
    final mock = MockClient((_) async => http.Response(
          jsonEncode({
            'tag_name': 'v0.1.1',
            'html_url': 'https://example.test',
            'assets': [
              {'name': 'good.tar.gz', 'browser_download_url': 'https://x/a', 'size': 10},
              {'name': 'no-url'},
              {'browser_download_url': 'https://x/b', 'size': 10},
              {'name': 'zero', 'browser_download_url': 'https://x/c', 'size': 0},
            ],
          }),
          200,
        ));

    final release = await check(() => mock).fetchLatest();
    expect(release!.assets, hasLength(1));
    expect(release.assets.single.name, 'good.tar.gz');
  });
}

/// Stands in for a real socket failure without importing dart:io, so this
/// suite stays runnable on every target.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
