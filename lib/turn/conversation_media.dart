import 'dart:typed_data';

import '../data/models/chat_message.dart';
import '../data/models/conversation.dart';
import '../data/models/message_block.dart';
import '../data/models/studio_result.dart';

/// An image this conversation has already produced, described well enough for
/// either backend to get the bytes back.
///
/// The three fields are three different lifetimes of the same picture:
/// [pngBytes] is the copy still in memory from the session that made it,
/// [assetId] is where those bytes went once the conversation was persisted,
/// and [seed] is how demo mode repaints one it never stored bytes for.
class GeneratedImage {
  final String alt;
  final Uint8List? pngBytes;
  final String? assetId;
  final int? seed;

  const GeneratedImage({
    required this.alt,
    this.pngBytes,
    this.assetId,
    this.seed,
  });
}

/// The most recent image the assistant generated in [conversation], or null if
/// it has not made one.
///
/// Both shapes count: a live provider's [ImageBlock] and demo mode's
/// [ImageResult] card, since from the user's side both are "the image you just
/// made" and either can be the one they want on a page.
GeneratedImage? latestGeneratedImage(Conversation conversation) {
  for (final message in conversation.messages.reversed) {
    if (message.role != MessageRole.assistant) continue;
    for (final block in message.blocks.reversed) {
      if (block is ImageBlock) {
        return GeneratedImage(
          alt: block.alt,
          pngBytes: block.pngBytes,
          assetId: block.assetId,
        );
      }
    }
    final result = message.studioResult;
    if (result is ImageResult) {
      return GeneratedImage(alt: result.prompt, seed: result.seed);
    }
  }
  return null;
}

/// A definite reference back to a picture that already exists — "this image",
/// "that photo", "the logo you made".
///
/// Definite on purpose. "Add **a** hero image to the website" asks for a new
/// one and must keep going to the image provider; "put **this** image in the
/// website" is about the one already on screen, and generating a second one
/// answers a question nobody asked.
final _existingImageReference = RegExp(
    r'\b(this|that|these|those|the)\s+(\w+\s+){0,3}'
    r'(images?|photos?|pictures?|logos?|graphics?|illustrations?|'
    r'artworks?|renders?|renderings?)\b');

/// The same request made with a bare pronoun: "put **it** in a website",
/// "turn it into a landing page", "a site featuring it".
///
/// Most people say it this way — the picture is right there on screen, so
/// naming it again feels redundant. Requiring the noun meant "put it in a
/// website" fell through and the model was left to invent a stand-in.
///
/// The verb (or preposition) has to sit immediately before the pronoun, which
/// is what keeps an unrelated "it" out: "build a page and put a contact form
/// in it" does not match, because the pronoun there is the *destination*.
final _pronounReference = RegExp(
    r'\b(put|use|add|include|place|insert|drop|feature|show|display|embed|'
    r'turn|make|with|featuring|using|around)\s+'
    r'(it|this|that|them|these|those)\b');

/// Somewhere for the image to go.
final _pageReference = RegExp(
    r'\b(website|web site|site|page|landing|homepage|home page|portfolio|'
    r'blog|app|artifact)\b');

/// The already-generated image a page-building turn should carry, or null when
/// this turn is not that.
///
/// Requires both halves — a reference to something that already exists *and*
/// somewhere to put it — so that "make this image bigger" (no page) and "build
/// me a site with photos" (nothing referred to) are both left alone.
GeneratedImage? existingImageForPage(
  Conversation conversation,
  String userInput,
) {
  final lower = userInput.toLowerCase();
  final refersBack = _existingImageReference.hasMatch(lower) ||
      _pronounReference.hasMatch(lower);
  if (!refersBack) return null;
  if (!_pageReference.hasMatch(lower)) return null;
  return latestGeneratedImage(conversation);
}
