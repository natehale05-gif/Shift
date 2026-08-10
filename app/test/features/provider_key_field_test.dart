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
          {String? saved, ProbeOutcome? outcome}) =>
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
          ),
        ),
      );

  testWidgets('there is nothing to test until there is a key', (t) async {
    await t.pumpWidget(host(anthropic));
    expect(find.text('Test connection'), findsNothing);
  });

  testWidgets('a provider with no client offers no test', (t) async {
    // Offering to test something that cannot run is the kind of button that
    // erodes trust in every other one.
    await t.pumpWidget(host(groq, saved: '••••••••9876'));
    expect(find.text('Test connection'), findsNothing);
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
