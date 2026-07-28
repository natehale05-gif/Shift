import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/features/memory/memory_service.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/memory_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MemoryService.extractFacts', () {
    test('pulls name, location, job, and preferences from a message', () {
      final facts = MemoryService.extractFacts(
        "Hi, my name is Nate. I live in Kyoto and I work as a product "
        "designer. I really like TypeScript.",
      );
      expect(facts, contains("User's name is Nate"));
      expect(facts.any((f) => f.contains('Kyoto')), isTrue);
      expect(facts.any((f) => f.toLowerCase().contains('product designer')),
          isTrue);
      expect(facts.any((f) => f.contains('TypeScript')), isTrue);
    });

    test('returns nothing for a message with no durable facts', () {
      expect(MemoryService.extractFacts('what is the capital of France?'),
          isEmpty);
    });

    test('honours an explicit "remember that"', () {
      final facts =
          MemoryService.extractFacts('Please remember that I am vegetarian.');
      expect(facts.any((f) => f.toLowerCase().contains('vegetarian')), isTrue);
    });
  });

  group('MemoryStore', () {
    test('adds facts, dedupes, toggles, and reflects into activeTexts',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = MemoryStore(persistence: PersistenceService());
      await store.load();

      expect(store.addFact("User's name is Nate"), isTrue);
      expect(store.addFact("user's name is nate"), isFalse); // dedupe
      expect(store.entries, hasLength(1));
      expect(store.activeTexts, contains("User's name is Nate"));

      // Muting an entry drops it from activeTexts but keeps it listed.
      store.toggleEntry(store.entries.first.id);
      expect(store.entries, hasLength(1));
      expect(store.activeTexts, isEmpty);

      // The master switch hides everything.
      store.toggleEntry(store.entries.first.id); // re-enable
      expect(store.activeTexts, hasLength(1));
      store.setEnabled(false);
      expect(store.activeTexts, isEmpty);
    });

    test('persists across reloads over the same persistence', () async {
      SharedPreferences.setMockInitialValues({});
      final persistence = PersistenceService();
      final store = MemoryStore(persistence: persistence);
      await store.load();
      store.addFact('Lives in Kyoto');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final reloaded = MemoryStore(persistence: persistence);
      await reloaded.load();
      expect(reloaded.entries.map((e) => e.text), contains('Lives in Kyoto'));
    });
  });
}
