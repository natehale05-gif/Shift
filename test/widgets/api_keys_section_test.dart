import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/core/theme/app_theme.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';
import 'package:shift_ai/features/settings/api_keys_section.dart';

Widget host(ApiKeysStore store) => ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: ApiKeysSection()),
        ),
      ),
    );

String fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Persistence already holding [keys], as after a restart.
  ///
  /// The store talks to an IndexedDB shim whose futures need a real event
  /// loop, which `testWidgets`' fake clock does not turn — hence `runAsync`
  /// around every store call.
  Future<PersistenceService> stored(
    WidgetTester tester,
    Map<String, String> keys,
  ) async {
    late PersistenceService persistence;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      persistence = PersistenceService();
      final seed = ApiKeysStore(persistence: persistence);
      await seed.load();
      for (final entry in keys.entries) {
        await seed.setKey(entry.key, entry.value);
      }
    });
    return persistence;
  }

  testWidgets('a stored key appears once loading finishes', (tester) async {
    // HomeShell's IndexedStack builds every screen at launch, so this field is
    // constructed *before* ApiKeysStore.load() resolves. Seeding the
    // controller once in initState left it permanently empty: the key was
    // saved, live mode was on, and the field still showed its placeholder —
    // which reads as "it didn't save".
    final persistence = await stored(tester, {'anthropic': 'sk-ant-STORED'});
    final store = ApiKeysStore(persistence: persistence);

    await tester.pumpWidget(host(store));
    expect(fieldText(tester), isEmpty, reason: 'nothing loaded yet');

    await tester.runAsync(() => store.load());
    await tester.pump();

    expect(fieldText(tester), 'sk-ant-STORED');
  });

  testWidgets('each provider shows its own key', (tester) async {
    final persistence = await stored(tester, {
      'anthropic': 'sk-ant-AAA',
      'gemini': 'AIza-BBB',
    });
    final store = ApiKeysStore(persistence: persistence);
    await tester.runAsync(() => store.load());

    await tester.pumpWidget(host(store));
    await tester.pump();
    expect(fieldText(tester), 'sk-ant-AAA');

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Google Gemini').last);
    await tester.pump(const Duration(seconds: 1));

    expect(fieldText(tester), 'AIza-BBB');
    expect(store.keyFor('anthropic'), 'sk-ant-AAA',
        reason: 'switching must not disturb the other provider');
  });

  testWidgets('typing is not clobbered by the store echoing back',
      (tester) async {
    // The sync must not fight the user: every keystroke writes to the store,
    // which rebuilds this widget, which must not then reset the field.
    final persistence = await stored(tester, {});
    final store = ApiKeysStore(persistence: persistence);
    await tester.runAsync(() => store.load());

    await tester.pumpWidget(host(store));
    await tester.enterText(find.byType(TextField).first, 'sk-ant-TYPED');
    await tester.pump();

    expect(fieldText(tester), 'sk-ant-TYPED');
    expect(store.keyFor('anthropic'), 'sk-ant-TYPED');
  });

  testWidgets('clearing the field clears the stored key', (tester) async {
    final persistence = await stored(tester, {'anthropic': 'sk-ant-AAA'});
    final store = ApiKeysStore(persistence: persistence);
    await tester.runAsync(() => store.load());

    await tester.pumpWidget(host(store));
    await tester.pump();
    expect(fieldText(tester), 'sk-ant-AAA');

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();

    expect(fieldText(tester), isEmpty);
    expect(store.hasKey('anthropic'), isFalse);
  });
}
