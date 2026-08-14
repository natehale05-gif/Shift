import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/features/styles/style_editor.dart';

/// Opens the dialog from a real button, which is the only way to get a
/// `BuildContext` under a `Navigator`.
Future<void> _open(
  WidgetTester tester, {
  String initialName = '',
  String initialInstructions = '',
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => showStyleEditorDialog(
            context,
            initialName: initialName,
            initialInstructions: initialInstructions,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the commit button is disabled until both fields are filled',
      (tester) async {
    await _open(tester);

    FilledButton button() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'));

    expect(button().onPressed, isNull,
        reason: 'an empty form cannot be submitted');

    // A name alone is not enough — a style with no instructions does nothing.
    await tester.enterText(find.byType(TextField).first, 'Playful');
    await tester.pump();
    expect(button().onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'Be light and warm.');
    await tester.pump();
    expect(button().onPressed, isNotNull,
        reason: 'a button that looks pressable must do something when pressed');
  });

  testWidgets('whitespace is not content', (tester) async {
    await _open(tester);

    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.enterText(find.byType(TextField).last, '   ');
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('editing an existing style opens filled in and ready to save',
      (tester) async {
    await _open(
      tester,
      initialName: 'Executive summary',
      initialInstructions: 'Lead with the decision.',
    );

    expect(find.text('Edit style'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNotNull,
    );
  });
}
