import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/features/settings/provider_key_field.dart';
import 'package:shift/providers/probe.dart';
import 'package:shift/providers/registry.dart';

/// The control that answers the question a failed chat turn cannot: whether
/// the key itself is fine, or whether the request never got out.
void main() {
  final anthropic = kProviders.firstWhere((p) => p.id == 'anthropic');
  final groq = kProviders.firstWhere((p) => p.id == 'groq');

  Widget host(ProviderDescriptor provider,
          {String? saved, ProbeOutcome? outcome, bool onWeb = false}) =>
      MaterialApp(
        theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
        home: Scaffold(
          body: ProviderKeyField(
            provider: provider,
            saved: saved,
            onSave: (_) {},
            onRemove: () {},
            readKey: () => 'sk-ant-real',
            probe: (_) async => outcome ?? ProbeOutcome.working,
            // Passed rather than read from `kIsWeb`, which is false in every
            // test in this app — so the branch that only exists on the web
            // would otherwise be one no test could enter.
            onWeb: onWeb,
          ),
        ),
      );

  testWidgets('there is nothing to test until there is a key', (t) async {
    await t.pumpWidget(host(anthropic));
    expect(find.text('Test connection'), findsNothing);
  });

  testWidgets('every keyed provider can be tested', (t) async {
    // This asserted the opposite while Anthropic was the only wired client —
    // Groq had a key field and no way to check it. Now that the Gemini and
    // OpenAI-compatible wires exist, a row that can hold a key and cannot be
    // tested would be an unexplained gap rather than an honest one.
    await t.pumpWidget(host(groq, saved: '••••••••9876'));
    expect(find.text('Test connection'), findsOneWidget);
  });

  testWidgets('it reports what came back, in a sentence', (t) async {
    await t.pumpWidget(host(anthropic,
        saved: '••••••••9876', outcome: ProbeOutcome.blocked));

    await t.tap(find.text('Test connection'));
    await t.pumpAndSettle();

    expect(find.text(probeSentence(ProbeOutcome.blocked)), findsOneWidget);
    // The distinction the whole control exists for: this must not read as a
    // problem with the key, which is what a failed chat turn implied.
    expect(find.textContaining('key was rejected'), findsNothing);
  });

  testWidgets('a working key says so plainly', (t) async {
    await t.pumpWidget(host(anthropic,
        saved: '••••••••9876', outcome: ProbeOutcome.working));

    await t.tap(find.text('Test connection'));
    await t.pumpAndSettle();

    expect(find.text(probeSentence(ProbeOutcome.working)), findsOneWidget);
  });

  group('what a browser can actually reach', () {
    // The report this came from: "some keys are not working in my desktop
    // browsers, I tried chrome and brave". Both browsers behaved correctly.
    // The app's advice — try another browser — was the wrong advice, and it
    // was given for a provider whose CORS behaviour is not established.

    testWidgets('an unverified provider says so before a key is pasted',
        (t) async {
      await t.pumpWidget(host(groq, onWeb: true));
      expect(find.textContaining('May not work in a browser'), findsOneWidget);
    });

    testWidgets('a verified one does not', (t) async {
      // Claude and Gemini were measured: preflight and real POST both carry
      // `access-control-allow-origin`. Warning about them would be noise, and
      // noise is what makes the real warning ignorable.
      await t.pumpWidget(host(anthropic, onWeb: true));
      expect(find.textContaining('May not work in a browser'), findsNothing);
    });

    testWidgets('and nothing is said off the web at all', (t) async {
      // There is no CORS outside a browser, so every provider works in the
      // desktop and mobile builds. Warning there would be false.
      await t.pumpWidget(host(groq));
      expect(find.textContaining('May not work in a browser'), findsNothing);
    });

    test('a blocked request stops prescribing another browser', () {
      final generic = probeSentence(ProbeOutcome.blocked, onWeb: false);
      final specific = probeSentence(ProbeOutcome.blocked,
          provider: groq, onWeb: true);

      expect(specific, isNot(generic));
      expect(specific, contains('Groq'));
      expect(specific, contains('desktop app'));
      // The sentence that sent somebody to a second browser. It may still be
      // the cause, and it is still named — but it is no longer the whole of
      // the advice.
      expect(specific, contains('content blocker'));
      expect(generic, contains('try another browser'));
    });

    test('a verified provider keeps the generic sentence', () {
      // Claude *is* reachable from a browser, so a blocked request there
      // really is something local — and saying "Claude may not allow calls
      // from a web page" would be a plain falsehood.
      expect(
        probeSentence(ProbeOutcome.blocked, provider: anthropic, onWeb: true),
        probeSentence(ProbeOutcome.blocked, onWeb: false),
      );
    });

    test('every outcome still produces its own sentence', () {
      // The invariant the whole probe exists for, re-asserted now that one of
      // the sentences has grown a variant.
      final sentences = [
        for (final outcome in ProbeOutcome.values)
          probeSentence(outcome, provider: groq, onWeb: true),
      ];
      expect(sentences.toSet(), hasLength(ProbeOutcome.values.length));
    });
  });

  testWidgets('every control clears the tap-target minimum', (t) async {
    // This test has caught controls in this app three times, so it follows
    // them onto every new row rather than staying where it started.
    await t.pumpWidget(host(anthropic, saved: '••••••••9876'));

    final buttons = find.byType(TextButton);
    expect(buttons, findsWidgets);
    for (var i = 0; i < buttons.evaluate().length; i++) {
      final size = t.getSize(buttons.at(i));
      expect(size.height, greaterThanOrEqualTo(kMinTouchTarget),
          reason: 'button $i is ${size.height} tall');
    }
  });
}
