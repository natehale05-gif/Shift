import 'package:flutter/material.dart';

/// The smallest a control may be on a touch screen.
///
/// Apple's guidance is 44pt and Material's is 48dp. A finger is roughly a
/// centimetre across and lands with its pad, not its tip, so anything smaller
/// is hit *near* rather than *on* — which reads as the app ignoring taps
/// rather than as the target being small.
const double kMinTouchTarget = 44;

/// Icon-button density that stays comfortable on a phone.
///
/// [VisualDensity.compact] takes 8 logical pixels off both axes, so an
/// `IconButton` that would be 48×48 becomes **40×40** — measured, not
/// estimated. That is fine under a mouse and four points short of Apple's
/// minimum under a thumb, and the chat's action row, the sidebar's menus, and
/// the copy button on every code block were all built that way.
///
/// [VisualDensity.adaptivePlatformDensity] is compact on desktop and standard
/// on iOS and Android, which is exactly the split wanted: the dense rows the
/// desktop layout was designed around, and full-size targets on the devices
/// that are touched.
VisualDensity get touchSafeDensity => VisualDensity.adaptivePlatformDensity;
