import 'package:flutter/foundation.dart';

enum ArtifactTab { preview, code }

/// UI state for the artifacts side panel: which artifact is open, which of
/// its versions is showing, and which tab. The artifact data itself lives on
/// the conversation (via [ConversationStore]); this store only points at it.
class ArtifactPanelStore extends ChangeNotifier {
  String? _artifactId;
  int _versionIndex = 0;
  ArtifactTab _tab = ArtifactTab.preview;
  bool _expanded = false;

  bool get isOpen => _artifactId != null;
  String? get artifactId => _artifactId;
  int get versionIndex => _versionIndex;
  ArtifactTab get tab => _tab;

  /// Whether the artifact fills the window instead of sharing it with the
  /// chat. A page squeezed into a 42%-wide column is being previewed at a
  /// width nobody will view it at, so the deliverable gets the whole screen
  /// on request. Below the side-by-side threshold the panel is full-screen
  /// regardless and this is ignored.
  bool get expanded => _expanded;

  void toggleExpanded() {
    _expanded = !_expanded;
    notifyListeners();
  }

  void open(String artifactId, {int? versionIndex}) {
    _artifactId = artifactId;
    if (versionIndex != null) _versionIndex = versionIndex;
    notifyListeners();
  }

  void close() {
    _artifactId = null;
    _versionIndex = 0;
    _tab = ArtifactTab.preview;
    _expanded = false;
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
