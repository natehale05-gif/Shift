import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../services/speech/speech_service.dart';

/// Voice dictation for the composer: owns the speech subscription and the
/// text-restore point, so the widget only has to say "toggle".
///
/// Transcripts are appended to whatever was already typed rather than
/// replacing it, which is why the text before dictation started has to be
/// remembered here.
class ComposerDictation {
  final TextEditingController controller;

  ComposerDictation(this.controller);

  bool listening = false;
  StreamSubscription<SpeechResult>? _subscription;
  String _textBeforeDictation = '';

  static bool get isSupported => SpeechService.isSupported;

  /// Starts or stops dictation. [onChanged] fires when [listening] flips, so
  /// the composer can repaint the mic button.
  void toggle({required void Function() onChanged}) {
    if (listening) {
      SpeechService.stop();
      listening = false;
      onChanged();
      return;
    }
    _textBeforeDictation =
        controller.text.isEmpty ? '' : '${controller.text.trimRight()} ';
    listening = true;
    onChanged();
    _subscription = SpeechService.listen().listen(
      (result) {
        controller.text = _textBeforeDictation + result.transcript;
        controller.selection =
            TextSelection.collapsed(offset: controller.text.length);
      },
      onDone: () {
        listening = false;
        onChanged();
      },
    );
  }

  void dispose() {
    _subscription?.cancel();
    SpeechService.stop();
  }
}
