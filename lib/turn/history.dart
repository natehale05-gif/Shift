/// What was already said, in a shape every provider can be handed.
///
/// **Pairs rather than a flat list of messages, and that is the load-bearing
/// decision.** Anthropic rejects two messages with the same role in a row, and
/// a transcript has plenty of ways to produce one: a reply that failed, a reply
/// that is still arriving, a turn stopped before it said anything. A flat list
/// would need every one of those handled at the point of building the request,
/// in three clients, correctly. A pair that is missing half is simply not a
/// pair, so alternation holds by construction and there is nothing to get
/// wrong later.
class Exchange {
  /// What the person said.
  final String asked;

  /// What came back. An exchange with nothing here is never built.
  final String answered;

  const Exchange({required this.asked, required this.answered});
}

/// The most recent exchanges that fit, oldest first.
///
/// Two bounds, and both are about money as much as about limits: every turn
/// re-sends the whole history, so an unbounded transcript costs more on each
/// message than the one before it, forever. [maxExchanges] keeps a long
/// conversation from becoming an expensive one; [maxChars] keeps a
/// conversation of *few but enormous* turns — a pasted document, a generated
/// page — from doing the same.
///
/// Trimmed from the **most recent backwards**, because the end of a
/// conversation is what a follow-up refers to. Dropping the beginning loses
/// the topic; dropping the end loses the question.
///
/// Nothing is summarised and nothing is elided with a marker. A model told
/// "[…earlier messages omitted…]" behaves as though it is missing something,
/// which it is; a model simply given the last N turns behaves as though the
/// conversation started there, which is the better failure.
List<Exchange> trimHistory(
  List<Exchange> history, {
  int maxExchanges = 20,
  int maxChars = 24000,
}) {
  final kept = <Exchange>[];
  var chars = 0;

  for (final exchange in history.reversed) {
    if (kept.length >= maxExchanges) break;
    final size = exchange.asked.length + exchange.answered.length;
    // The first exchange is kept whatever its size: dropping everything and
    // sending a bare follow-up is worse than one oversized turn, and a single
    // message longer than the budget is the model's problem to refuse rather
    // than ours to silently discard.
    if (kept.isNotEmpty && chars + size > maxChars) break;
    chars += size;
    kept.add(exchange);
  }

  return kept.reversed.toList();
}
