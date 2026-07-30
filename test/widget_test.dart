import 'package:flutter_test/flutter_test.dart';

import 'package:shift_ai/app.dart';

void main() {
  testWidgets('ShiftAiApp boots to the chat screen', (tester) async {
    await tester.pumpWidget(const ShiftAiApp());

    // Deliberately not `pumpAndSettle`. The shell is an `IndexedStack`, so
    // every screen is built at boot — including Settings, and therefore the
    // account card, which shows an indeterminate spinner while it works out
    // whether there is a session to restore. `pumpAndSettle` waits for *all*
    // animation to stop, and a spinner by definition never stops, so this ran
    // the fake clock out the moment the app gained a backend to check with.
    //
    // The assertion below is the whole point of the test — that the app boots
    // and lands on the chat screen — and it needs a couple of frames, not
    // quiescence.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SHIFT AI'), findsWidgets);
  });
}
