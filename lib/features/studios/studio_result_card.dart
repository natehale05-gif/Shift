


/// Renders a mock studio result inline in the chat. Every visual/audio/video
/// artifact here is procedurally generated at render time — nothing is a
/// real diffusion/video model output. Audio is a real (synthesized) WAV file
/// so playback and download both work; images/video download a real PNG
/// snapshot of the rendered art/thumbnail.
library;

import '../../data/models/studio_result.dart';
import 'audio/audio_result_view.dart';
import 'brand_pack/brand_pack_result_view.dart';
import 'code/code_result_view.dart';
import 'copy/copy_result_view.dart';
import 'deck/deck_result_view.dart';
import 'image/image_result_view.dart';
import 'package:flutter/material.dart';
import 'short_reels/short_reels_result_view.dart';
import 'translate/translate_result_view.dart';
import 'video/video_result_view.dart';

class StudioResultCard extends StatelessWidget {
  final StudioResult result;

  const StudioResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return switch (result) {
      ImageResult r => ImageResultView(result: r),
      VideoResult r => VideoResultView(result: r),
      AudioResult r => AudioResultView(result: r),
      CopyResult r => CopyResultView(result: r),
      CodeResult r => CodeResultView(result: r),
      TranslateResult r => TranslateResultView(result: r),
      DeckResult r => DeckResultView(result: r),
      BrandPackResult r => BrandPackResultView(result: r),
      ShortReelsPackResult r => ShortReelsResultView(result: r),
    };
  }
}


