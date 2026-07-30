import 'dart:typed_data';

import '../../data/models/artifact.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/message_block.dart';
import '../../data/models/studio_result.dart';

/// One piece of a turn as a provider will see it.
sealed class HistoryPart {
  const HistoryPart();
}

class HistoryText extends HistoryPart {
  final String text;
  const HistoryText(this.text);
}

class HistoryImage extends HistoryPart {
  final Uint8List pngBytes;
  const HistoryImage(this.pngBytes);
}

/// One turn, provider-agnostic.
class HistoryTurn {
  final MessageRole role;
  final List<HistoryPart> parts;
  const HistoryTurn(this.role, this.parts);

  String get text =>
      parts.whereType<HistoryText>().map((p) => p.text).join('\n\n');
  bool get hasImage => parts.any((p) => p is HistoryImage);
}

/// Builds the conversation every provider is shown.
///
/// One builder rather than one per client, because the point of the app is
/// that several providers work on the same chat. They each used to flatten it
/// themselves, and each flattened it the same lossy way:
///
/// * an assistant turn became `message.text` and nothing else, so generated
///   images, voiceovers and artifacts left no trace at all; and
/// * **any turn whose text was empty was skipped entirely** — which is exactly
///   what an image-only or voiceover-only turn looks like. The model was not
///   told the turn had happened, so a follow-up referring to "it" referred to
///   nothing.
///
/// Now every turn survives. A block that cannot be sent as itself is sent as a
/// short note — "[generated image: a pink flower]" — so a model that cannot
/// see pictures still knows one exists and what it was of.
///
/// Pure: messages in, turns out. No I/O, no provider knowledge.
List<HistoryTurn> buildHistory(
  List<ChatMessage> messages, {
  /// Off for providers that cannot take images. They get the notes instead,
  /// which is a real capability difference rather than the accidental data
  /// loss this replaces.
  bool includeImages = true,

  /// Only the most recent few images are attached. History is unbounded and
  /// images are the expensive part; the notes still cover the older ones.
  int maxImages = 3,
}) {
  final turns = <HistoryTurn>[];
  for (final message in messages) {
    if (message.role == MessageRole.system) continue;
    final parts = message.role == MessageRole.user
        ? _userParts(message)
        : _assistantParts(message);
    if (parts.isEmpty) continue;
    turns.add(HistoryTurn(message.role, parts));
  }

  if (!includeImages) {
    return [
      for (final turn in turns)
        HistoryTurn(turn.role,
            turn.parts.where((p) => p is! HistoryImage).toList()),
    ];
  }

  // Keep the newest images, drop the rest to notes — walking backwards so
  // "the most recent" means the ones a follow-up is most likely about.
  var budget = maxImages;
  final kept = <HistoryTurn>[];
  for (final turn in turns.reversed) {
    if (!turn.hasImage) {
      kept.add(turn);
      continue;
    }
    final parts = <HistoryPart>[];
    for (final part in turn.parts) {
      if (part is HistoryImage) {
        if (budget <= 0) continue;
        budget--;
      }
      parts.add(part);
    }
    kept.add(HistoryTurn(turn.role, parts));
  }
  return kept.reversed.toList();
}

List<HistoryPart> _userParts(ChatMessage message) {
  final text = message.text.trim();
  return text.isEmpty ? const [] : [HistoryText(text)];
}

List<HistoryPart> _assistantParts(ChatMessage message) {
  final parts = <HistoryPart>[];
  for (final block in message.blocks) {
    switch (block) {
      case TextBlock(:final text):
        if (text.trim().isNotEmpty) parts.add(HistoryText(text));
      case ImageBlock(:final alt, :final pngBytes):
        // The note goes in either way: it names what the picture was of, which
        // is what a later "put it in a website" is referring to.
        parts.add(HistoryText('[generated image: ${alt.trim()}]'));
        if (pngBytes != null) parts.add(HistoryImage(pngBytes));
      case ArtifactRefBlock(:final title, :final kind):
        parts.add(HistoryText(
            '[built "$title" — ${_artifactWord(kind)}, shown to the user in '
            'the side panel]'));
      // The model's own scratch and its tool chips are not worth replaying —
      // they are about how the last answer was produced, not what it was.
      case ThinkingBlock():
      case ToolUseBlock():
        break;
    }
  }

  final result = message.studioResult;
  if (result != null) parts.add(HistoryText(_resultNote(result)));

  // Blocks are empty on directly-constructed and older messages, which still
  // carry flat text.
  if (parts.isEmpty && message.text.trim().isNotEmpty) {
    parts.add(HistoryText(message.text.trim()));
  }
  return parts;
}

String _artifactWord(ArtifactKind kind) =>
    switch (kind) { ArtifactKind.html => 'a web page', _ => 'a code file' };

String _resultNote(StudioResult result) => switch (result) {
      ImageResult(:final prompt) => '[generated an image: $prompt]',
      VideoResult(:final prompt) => '[generated a video: $prompt]',
      AudioResult(:final kind, :final title, :final transcript) =>
        kind == AudioKind.voice
            ? '[generated a voiceover — "$title". Script: '
                '${transcript ?? ''}]'
            : '[generated a music track — "$title"]',
      TranslateResult(:final targetLanguage) =>
        '[produced a translation into $targetLanguage]',
      DeckResult(:final title) => '[built a slide deck: "$title"]',
      BrandPackResult() => '[built a brand pack]',
      ShortReelsPackResult() => '[built a pack of short-form reels]',
      CopyResult() => '[wrote copy]',
      CodeResult(:final filename) => '[wrote $filename]',
    };
