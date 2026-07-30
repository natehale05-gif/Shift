import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/core/state/artifact_panel_store.dart';

void main() {
  test('a fresh panel is closed, on preview, and not expanded', () {
    final panel = ArtifactPanelStore();
    expect(panel.isOpen, isFalse);
    expect(panel.tab, ArtifactTab.preview);
    expect(panel.expanded, isFalse);
  });

  test('expanding is a toggle', () {
    final panel = ArtifactPanelStore()..open('a1');
    expect(panel.expanded, isFalse);

    panel.toggleExpanded();
    expect(panel.expanded, isTrue);

    panel.toggleExpanded();
    expect(panel.expanded, isFalse);
  });

  test('closing leaves nothing behind for the next artifact', () {
    // Otherwise the next artifact you open inherits the last one's full-screen
    // state and tab, which reads as the app deciding for you.
    final panel = ArtifactPanelStore()
      ..open('a1', versionIndex: 2)
      ..selectTab(ArtifactTab.code)
      ..toggleExpanded();

    panel.close();

    expect(panel.isOpen, isFalse);
    expect(panel.expanded, isFalse);
    expect(panel.tab, ArtifactTab.preview);
    expect(panel.versionIndex, 0);
  });

  test('opening an update lands on the newest version', () {
    final panel = ArtifactPanelStore()..open('a1');
    expect(panel.versionIndex, 0);

    panel.open('a1', versionIndex: 1);
    expect(panel.versionIndex, 1);
  });

  test('the version pointer is clamped when versions shrink', () {
    final panel = ArtifactPanelStore()..open('a1', versionIndex: 4);
    panel.clampVersion(2);
    expect(panel.versionIndex, 1);
  });

  test('listeners are notified when the panel expands', () {
    var notifications = 0;
    final panel = ArtifactPanelStore()..addListener(() => notifications++);

    panel.toggleExpanded();
    expect(notifications, 1);
  });
}
