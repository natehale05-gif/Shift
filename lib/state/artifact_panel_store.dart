import 'package:flutter/foundation.dart';

enum ArtifactTab { preview, code }

/// UI state for the artifacts side panel: which artifact is open, which of
/// its versions is showing, and which tab. The artifact data itself lives on
/// the conversation (via [ConversationStore]); this store only points at it.
class ArtifactPanelStore extends ChangeNotifier {
  String? _artifactId;
  int _versionIndex = 0;
  ArtifactTab _tab = ArtifactTab.preview;

  bool get isOpen => _artifactId != null;
  String? get artifactId => _artifactId;
  int get versionIndex => _versionIndex;
  ArtifactTab get tab => _tab;

  void open(String artifactId, {int? versionIndex}) {
    _artifactId = artifactId;
    if (versionIndex != null) _versionIndex = versionIndex;
    notifyListeners();
  }

  void close() {
    _artifactId = null;
    _versionIndex = 0;
    _tab = ArtifactTab.preview;
    notifyListeners();
  }

  void selectTab(ArtifactTab tab) {
    if (_tab == tab) return;
    _tab = tab;
    notifyListeners();
  }

  void selectVersion(int index) {
    if (_versionIndex == index) return;
    _versionIndex = index;
    notifyListeners();
  }

  /// Keeps the version pointer valid when an artifact gains versions or the
  /// panel is pointed at a different artifact than it was opened for.
  void clampVersion(int versionCount) {
    if (_versionIndex >= versionCount) {
      _versionIndex = versionCount - 1;
    }
  }
}
