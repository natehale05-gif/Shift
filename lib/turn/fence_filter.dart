/// Splits a streaming model reply into prose, forwarded as it arrives, and
/// fenced code blocks, withheld.
///
/// A code-routed reply becomes an artifact, so streaming its fenced block into
/// the chat as well showed the same page twice: once as an unreadable wall of
/// markup in the transcript, once as the artifact. The prose around it
/// ("Here you go — the complete site…") is the part worth streaming.
///
/// Withholding has to survive chunk boundaries: a delta can end mid-marker,
/// with the first backtick of a fence in one chunk and the rest in the next.
/// So a partial marker is carried over rather than emitted.
///
/// The held text is kept verbatim, markers included, because it must be
/// replayable: if no artifact comes of it after all — a fenced block too short
/// to be a deliverable — the code belongs back in the conversation rather than
/// silently dropped. Replaying appends it, so in that fallback a block that
/// originally sat mid-reply ends up at the end. That is the price of not
/// knowing whether a block is a deliverable until the reply finishes, and it
/// is only paid on the path where the block turned out to be a snippet.
class FenceFilter {
  final _held = StringBuffer();
  final _carry = StringBuffer();
  bool _inFence = false;

  /// Everything held back so far, verbatim, fence markers included.
  String get heldText => _held.toString();

  /// Whether any fenced block was seen at all.
  bool get sawFence => _held.isNotEmpty;

  /// Whether a fenced block is open right now — i.e. the deliverable is being
  /// written this instant, rather than the prose around it.
  ///
  /// The UI needs the distinction: a code turn opens with a sentence or two
  /// and only then writes the file, and showing "Building" during the sentence
  /// claims work that has not started.
  bool get writingCode => _inFence;

  /// Consumes a streamed [chunk] and returns the prose safe to emit now.
  String feed(String chunk) {
    final text = (_carry..write(chunk)).toString();
    _carry.clear();

    final prose = StringBuffer();
    var cursor = 0;
    while (true) {
      final marker = text.indexOf('```', cursor);
      if (marker < 0) break;
      final segment = text.substring(cursor, marker);
      (_inFence ? _held : prose).write(segment);
      // The prose between two blocks — including the newline that separated
      // them — is emitted, so held blocks would otherwise run together as
      // ```…`````` and replay as broken markdown.
      if (!_inFence && _held.isNotEmpty && !_held.toString().endsWith('\n')) {
        _held.write('\n');
      }
      _held.write('```');
      _inFence = !_inFence;
      cursor = marker + 3;
    }

    // A trailing run of backticks may be the start of a marker that the next
    // chunk completes, so hold it rather than emitting it as prose.
    final tail = text.substring(cursor);
    var partial = 0;
    for (var length = tail.length < 2 ? tail.length : 2; length > 0; length--) {
      if (tail.endsWith('`' * length)) {
        partial = length;
        break;
      }
    }
    final settled = tail.substring(0, tail.length - partial);
    (_inFence ? _held : prose).write(settled);
    _carry.write(tail.substring(tail.length - partial));

    return prose.toString();
  }

  /// Whether the stream ended inside a fence that was never closed.
  ///
  /// True when a reply was cut off mid-block — the model hit its output
  /// ceiling, or the connection dropped.
  bool get unterminated => _inFence;

  /// Any prose still carried when the stream ends. Backticks left dangling
  /// here were never part of a real marker, so they are prose after all.
  String flush() {
    final remainder = _carry.toString();
    _carry.clear();
    if (_inFence) {
      _held.write(remainder);
      return '';
    }
    return remainder;
  }

  /// The held text in a form safe to put back into a reply.
  ///
  /// An unterminated block gets its closing marker, because markdown with an
  /// open fence renders every following message as code. Call after [flush].
  String replayText() {
    final text = _held.toString();
    if (!_inFence || text.isEmpty) return text;
    return text.endsWith('\n') ? '$text```' : '$text\n```';
  }
}
