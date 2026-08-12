import 'package:flutter/foundation.dart';

import '../core/device/device_class.dart';
import 'mode.dart';

/// Which mode is open, and the one place that can change it.
///
/// A store rather than widget state because the mode will be set from outside
/// the widget tree well before v2 is finished: an Apple Shortcut asking for a
/// note, Siri asking a question, a deep link into a project, the command bar.
/// Every one of those needs a way in that is not "tap the thing on screen".
class ShellController extends ChangeNotifier {
  AppMode _mode = AppMode.chat;

  /// What the user chose, if they chose. Null means follow the device.
  ///
  /// Seeded from `--dart-define=SHIFT_DEVICE_CLASS=phone|tablet|desktop`.
  /// That exists because the phone surface is otherwise unreachable from a
  /// desktop or a browser under automation — Chromium reports its host OS
  /// whatever user agent it is handed, so a phone-shaped emulation still comes
  /// through as a desktop and renders the desktop layout, correctly. Without
  /// this, half the shell could only ever be verified by a widget test, and a
  /// widget test cannot see a row of pills overflowing.
  ///
  /// Kept rather than removed after N0: it is equally the fastest way to
  /// answer a support question about a layout somebody is seeing.
  DeviceClass? _deviceOverride = _deviceClassFromEnvironment();

  static DeviceClass? _deviceClassFromEnvironment() {
    const value = String.fromEnvironment('SHIFT_DEVICE_CLASS');
    return switch (value) {
      'phone' => DeviceClass.phone,
      'tablet' => DeviceClass.tablet,
      'desktop' => DeviceClass.desktop,
      _ => null,
    };
  }

  AppMode get mode => _mode;
  DeviceClass? get deviceOverride => _deviceOverride;

  void openMode(AppMode next) {
    if (_mode == next) return;
    _mode = next;
    notifyListeners();
  }

  /// Settings' escape hatch from the automatic device class. Passing null
  /// hands the decision back to [deviceClassOf].
  void setDeviceOverride(DeviceClass? value) {
    if (_deviceOverride == value) return;
    _deviceOverride = value;
    notifyListeners();
  }
}
