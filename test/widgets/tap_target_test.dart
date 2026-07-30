import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/core/theme/app_theme.dart';
import 'package:shift_ai/core/theme/tap_targets.dart';
import 'package:shift_ai/features/chat/composer/send_button.dart';
import 'package:shift_ai/features/chat/composer/stop_button.dart';
import 'package:shift_ai/features/chat/message/action_icon.dart';

/// Runs [body] as if on [platform], resetting inside the test body — Flutter
/// asserts every debug variable is back to normal before the body returns, so
/// a tearDown is too late.
Future<void> _asPlatform(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );

/// Every tappable in [finder] is at least [kMinTouchTarget] on both axes.
void _expectTouchable(WidgetTester tester, Finder finder) {
  for (final element in finder.evaluate()) {
    final size = tester.getSize(find.byWidget(element.widget));
    expect(size.width, greaterThanOrEqualTo(kMinTouchTarget),
        reason: '${element.widget.runtimeType} is ${size.width} wide');
    expect(size.height, greaterThanOrEqualTo(kMinTouchTarget),
        reason: '${element.widget.runtimeType} is ${size.height} tall');
  }
}

void main() {

  testWidgets('the send button clears the minimum', (tester) async {
    // It was clamped to 34x34 by a SizedBox — ten points short, on the
    // single most-tapped control in the app.
    await _asPlatform(TargetPlatform.iOS, () async {
      await tester.pumpWidget(_host(SendButton(enabled: true, onPressed: () {})));
      _expectTouchable(tester, find.byType(IconButton));
    });
  });

  testWidgets('so does the stop button', (tester) async {
    // They swap places in the composer, so a difference between them would
    // move the target under the thumb mid-turn.
    await _asPlatform(TargetPlatform.iOS, () async {
      await tester.pumpWidget(_host(StopButton(onPressed: () {})));
      _expectTouchable(tester, find.byType(IconButton));
    });
  });

  testWidgets('and the message action icons', (tester) async {
    // VisualDensity.compact takes 8 logical pixels off both axes, so these
    // rendered at 40x40 — measured, not estimated.
    await _asPlatform(TargetPlatform.iOS, () async {
      await tester.pumpWidget(_host(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ActionIcon(tooltip: 'Copy', icon: Icons.copy, onPressed: () {}),
          ActionIcon(tooltip: 'Retry', icon: Icons.refresh, onPressed: () {}),
        ],
      )));
      _expectTouchable(tester, find.byType(IconButton));
    });
  });

  testWidgets('the send button still looks the same size', (tester) async {
    // The circle is 34 and the *button* is 44: the fix widens the hit area,
    // it does not grow the artwork. A larger purple circle would be a visual
    // change nobody asked for.
    await _asPlatform(TargetPlatform.iOS, () async {
      await tester.pumpWidget(_host(SendButton(enabled: true, onPressed: () {})));
      final circle = tester.getSize(find.descendant(
        of: find.byType(IconButton),
        matching: find.byType(Container),
      ));
      expect(circle.width, 34);
      expect(circle.height, 34);
    });
  });

  testWidgets('desktop keeps the dense rows it was designed around',
      (tester) async {
    await _asPlatform(TargetPlatform.macOS, () async {
      await tester.pumpWidget(_host(
        ActionIcon(tooltip: 'Copy', icon: Icons.copy, onPressed: () {}),
      ));
      expect(tester.getSize(find.byType(IconButton)).width, lessThan(48));
    });
  });
}
