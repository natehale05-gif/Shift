import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/usage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('records messages, persists, and reflects the fraction', () async {
    SharedPreferences.setMockInitialValues({});
    final persistence = PersistenceService();
    final store = UsageStore(persistence: persistence);
    await store.load();

    expect(store.used, 0);
    store.recordMessage();
    store.recordMessage();
    expect(store.used, 2);
    expect(store.remaining, UsageStore.dailyCap - 2);
    expect(store.fraction, closeTo(2 / UsageStore.dailyCap, 1e-9));

    await Future<void>.delayed(const Duration(milliseconds: 20));
    final reloaded = UsageStore(persistence: persistence);
    await reloaded.load();
    expect(reloaded.used, 2);
  });

  test('rolls over to zero when the stored day is stale', () async {
    SharedPreferences.setMockInitialValues({});
    final persistence = PersistenceService();
    // Seed a counter from an old day.
    await persistence
        .saveUsageCounter({'day': '2000-1-1', 'count': 17});

    final store = UsageStore(persistence: persistence);
    await store.load();
    expect(store.used, 0, reason: 'a new day resets the counter');
  });
}
