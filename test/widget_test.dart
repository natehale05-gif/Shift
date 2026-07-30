import 'package:flutter_test/flutter_test.dart';

import 'package:shift_ai/app.dart';

void main() {
  testWidgets('ShiftAiApp boots to the chat screen', (tester) async {
    await tester.pumpWidget(const ShiftAiApp());
    await tester.pumpAndSettle();

    expect(find.text('SHIFT AI'), findsWidgets);
  });
}
