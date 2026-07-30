import 'package:flutter_test/flutter_test.dart';

import 'package:shift_ai/app.dart';

void main() {
  testWidgets('ShiftAiApp boots to the chat screen', (tester) async {
    await tester.pumpWidget(const ShiftAiApp());
    // Not pumpAndSettle: a blank chat now has an animal walking back and forth
    // above the greeting, and a repeating animation means the tree never
    // settles. Fixed pumps get past the boot frames without waiting for a
    // quiet state that no longer exists.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('SHIFT AI'), findsWidgets);
  });
}
