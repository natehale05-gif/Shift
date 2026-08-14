import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shift/core/update/update_check.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/data/update_store.dart';

String _releaseJson(String tag) => jsonEncode({
      'tag_name': tag,
      'html_url': 'https://github.com/natehale05-gif/Shift/releases/tag/$tag',
      'assets': const [],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int requests;
  // A real file, not a fake map: the store persists its throttle and its
  // dismissal, and the tests below reload from it. A fake that forgot would
  // make "the throttle survives a restart" untestable, which is the only
  // interesting thing about the throttle.
  late Directory dir;

  /// A store running [version], answering every check with [tag].
  Future<UpdateStore> store(
    String version, {
    String tag = 'v0.1.1',
    int statusCode = 200,
    KvStore? kv,
  }) async {
    PackageInfo.setMockInitialValues(
      appName: 'SHIFT AI',
      packageName: 'club.shiftai.app',
      version: version,
      buildNumber: '1',
      buildSignature: '',
    );
    final client = MockClient((_) async {
      requests++;
      return http.Response(_releaseJson(tag), statusCode);
    });
    final s = UpdateStore(
      kv ?? KvStore(path: '${dir.path}/kv.json'),
      check: UpdateCheck(clientFactory: () => client),
    );
    await s.load();
    return s;
  }

  setUp(() {
    requests = 0;
    dir = Directory.systemTemp.createTempSync('shift_update_test');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('reads the running version off the packaged manifest', () async {
    final s = await store('0.1.0');
    expect(s.currentVersion, '0.1.0');
    expect(s.status, UpdateStatus.idle);
  });

  test('a newer tag becomes available and prompts', () async {
    final s = await store('0.1.0', tag: 'v0.1.1');
    await s.checkNow();

    expect(s.status, UpdateStatus.available);
    expect(s.latest!.tag, 'v0.1.1');
    expect(s.shouldPrompt, isTrue);
  });

  test('the same tag is up to date and does not prompt', () async {
    final s = await store('0.1.0', tag: 'v0.1.0');
    await s.checkNow();

    expect(s.status, UpdateStatus.upToDate);
    expect(s.shouldPrompt, isFalse);
  });

  test('a 404 fails rather than claiming to be current', () async {
    // Before the first release exists this is what every launch sees. It
    // must not read as "you're on the latest version" -- the app has no
    // idea whether it is.
    final s = await store('0.1.0', statusCode: 404);
    await s.checkNow();

    expect(s.status, UpdateStatus.failed);
    expect(s.status, isNot(UpdateStatus.upToDate));
    expect(s.shouldPrompt, isFalse);
  });

  test('dismissing hides this version only', () async {
    final kv = KvStore(path: '${dir.path}/kv.json');
    final s = await store('0.1.0', tag: 'v0.1.1', kv: kv);
    await s.checkNow();
    expect(s.shouldPrompt, isTrue);

    await s.dismiss();
    expect(s.shouldPrompt, isFalse);
    expect(s.status, UpdateStatus.available, reason: 'Settings still reports it');

    // A later release prompts again rather than inheriting the dismissal.
    final next =
        await store('0.1.0', tag: 'v0.2.0', kv: KvStore(path: '${dir.path}/kv.json'));
    await next.checkNow();
    expect(next.shouldPrompt, isTrue);
  });

  test('an automatic check is throttled but the manual one is not', () async {
    final s = await store('0.1.0', kv: KvStore(path: '${dir.path}/kv.json'));

    await s.checkIfDue();
    expect(requests, 1);

    // Same day, fresh launch: the stored timestamp suppresses the request.
    final relaunched =
        await store('0.1.0', kv: KvStore(path: '${dir.path}/kv.json'));
    await relaunched.checkIfDue();
    expect(requests, 1, reason: 'ten launches a day cost one request');

    await relaunched.checkNow();
    expect(requests, 2, reason: 'the button always checks');
  });

  test('a stale timestamp lets the automatic check through', () async {
    final stale = KvStore(path: '${dir.path}/kv.json');
    await stale.load();
    await stale.put(
      'update.checkedAt',
      DateTime.now().subtract(UpdateStore.checkInterval * 2).toIso8601String(),
    );

    final s = await store('0.1.0', kv: KvStore(path: '${dir.path}/kv.json'));
    await s.checkIfDue();
    expect(requests, 1);
  });
}
