import 'package:flutter_test/flutter_test.dart';
import 'package:shift/providers/registry.dart';
import 'package:shift/providers/select.dart';
import 'package:shift/turn/capability.dart';

bool Function(String) only(Set<String> ids) => ids.contains;
bool none(String _) => false;
bool all(String _) => true;

void main() {
  group('choosing who does a step', () {
    test('the preferred provider wins when several are usable', () {
      final choice = chooseProvider(Capability.text, usable: all);
      expect(choice!.provider.id, 'anthropic');
    });

    test('a single available provider is used even when it is not preferred',
        () {
      // The v1 bug this replaces: a Gemini-only user asking for a page matched
      // no code-capable provider, so the turn fell through to the simulated
      // demo while the key they were paying for sat unused.
      final choice =
          chooseProvider(Capability.text, usable: only({'gemini'}));
      expect(choice!.provider.id, 'gemini');
      expect(choice.model.can, contains(Capability.text));
    });

    test('image resolves to the image leader, not the text leader', () {
      // The two-provider turn depends on this disagreeing with the text
      // answer. If both resolved to the same provider the headline feature
      // would still "work" and would quietly be one model doing everything.
      final image = chooseProvider(Capability.image, usable: all);
      final text = chooseProvider(Capability.text, usable: all);
      expect(image!.provider.id, 'gemini');
      expect(text!.provider.id, 'anthropic');
      expect(image.provider.id, isNot(text.provider.id));
    });

    test('nothing usable returns null rather than a default', () {
      expect(chooseProvider(Capability.text, usable: none), isNull);
    });

    test('a capability nobody declares returns null', () {
      // Video and music have no provider in this registry yet. The honest
      // answer is "nothing can do this", which the runner turns into a
      // sentence naming the capability — not a text model handed a video job.
      expect(chooseProvider(Capability.video, usable: all), isNull);
      expect(chooseProvider(Capability.music, usable: all), isNull);
    });

    test('a provider is never chosen for something it cannot do', () {
      for (final capability in Capability.values) {
        final choice = chooseProvider(capability, usable: all);
        if (choice == null) continue;
        expect(choice.model.can, contains(capability),
            reason: '${choice.provider.id}/${choice.model.id} was chosen for '
                '${capability.name} without declaring it');
      }
    });
  });

  group('pinning', () {
    test('a pin beats the ranking', () {
      final choice =
          chooseProvider(Capability.text, usable: all, pinned: 'mistral');
      expect(choice!.provider.id, 'mistral');
    });

    test('a pin that cannot do the step is ignored, not obeyed', () {
      // Pinning Groq and asking for an image should produce an image from
      // someone who can make one. Obeying the pin means a 400 from a text
      // endpoint; refusing the step entirely means the pin silently disables
      // half the app.
      final choice =
          chooseProvider(Capability.image, usable: all, pinned: 'groq');
      expect(choice!.provider.id, 'gemini');
    });

    test('a pin the account cannot use falls back rather than failing', () {
      final choice = chooseProvider(Capability.text,
          usable: only({'anthropic'}), pinned: 'mistral');
      expect(choice!.provider.id, 'anthropic');
    });

    test('an unknown pin is ignored', () {
      final choice =
          chooseProvider(Capability.text, usable: all, pinned: 'nope');
      expect(choice!.provider.id, 'anthropic');
    });
  });

  group('the table itself', () {
    test('every ranked capability has a model that can do it', () {
      // A rank without a matching model is a provider that will be chosen and
      // then have nothing to run — the failure appears one layer down, where
      // it reads as a provider error rather than a typo in this file.
      for (final provider in kProviders) {
        for (final capability in provider.ranks.keys) {
          expect(provider.modelFor(capability), isNotNull,
              reason: '${provider.id} is ranked for ${capability.name} but '
                  'has no model that declares it');
        }
      }
    });

    test('no two providers share a rank for the same capability', () {
      // Ties make selection depend on table order, which is invisible and
      // changes when someone inserts a provider alphabetically.
      for (final capability in Capability.values) {
        final ranks = [
          for (final p in kProviders)
            if (p.ranks[capability] != null) p.ranks[capability]!,
        ];
        expect(ranks.toSet().length, ranks.length,
            reason: 'two providers tie for ${capability.name}');
      }
    });

    test('provider ids are unique', () {
      final ids = kProviders.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });
}
