import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/core/update/update_check.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/update_store.dart';

String _releaseJson(String tag) => jsonEncode({
      'tag_name': tag,
      'html_url': 'https://github.com/natehale05-gif/Shift/releases/tag/$tag',
      'assets': const [],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int requests;

  /// A store running [version], answering every check with [tag].
  Future<UpdateStore> store(
    String version, {
    String tag = 'v0.1.1',
    int statusCode = 200,
    PersistenceService? persistence,
  }) async {
    SharedPreferences.setMockInitialValues({});
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
      persistence: persistence ?? PersistenceService(),
      check: UpdateCheck(clientFactory: () => client),
    );
    await s.load();
    return s;
  }

  setUp(() => requests = 0);

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
    final persistence = PersistenceService();
    final s = await store('0.1.0', tag: 'v0.1.1', persistence: persistence);
    await s.checkNow();
    expect(s.shouldPrompt, isTrue);

    await s.dismiss();
    expect(s.shouldPrompt, isFalse);
    expect(s.status, UpdateStatus.available, reason: 'Settings still reports it');

    // A later release prompts again rather than inheriting the dismissal.
    final next = await store('0.1.0', tag: 'v0.2.0', persistence: persistence);
    await next.checkNow();
    expect(next.shouldPrompt, isTrue);
  });

  test('an automatic check is throttled but the manual one is not', () async {
    final persistence = PersistenceService();
    final s = await store('0.1.0', persistence: persistence);

    await s.checkIfDue();
    expect(requests, 1);

    // Same day, fresh launch: the stored timestamp suppresses the request.
    final relaunched = await store('0.1.0', persistence: persistence);
    await relaunched.checkIfDue();
    expect(requests, 1, reason: 'ten launches a day cost one request');

    await relaunched.checkNow();
    expect(requests, 2, reason: 'the button always checks');
  });

  test('a stale timestamp lets the automatic check through', () async {
    final persistence = PersistenceService();
    await persistence.saveUpdateState({
      'checkedAt': DateTime.now()
          .subtract(UpdateStore.checkInterval * 2)
          .toIso8601String(),
    });

    final s = await store('0.1.0', persistence: persistence);
    await s.checkIfDue();
    expect(requests, 1);
  });
}
