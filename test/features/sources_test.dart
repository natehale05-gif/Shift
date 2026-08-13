import 'package:flutter_test/flutter_test.dart';
import 'package:shift/features/chat/turn_controller.dart';
import 'package:shift/turn/turn_event.dart';

/// What a sourced reply keeps, and what it must not claim.
void main() {
  Citation source(String host, {int? start, int? end}) => Citation(
        title: '$host article',
        url: Uri.parse('https://$host/a'),
        start: start,
        end: end,
      );

  test('a sourced reply keeps its sources across a reload', () {
    // A sourced answer that loses its sources on reload is worse than one that
    // never had them — the second is at least honest about what it is.
    final reply = Reply()
      ..write('It rained.')
      ..citations.addAll([source('a.test', start: 0, end: 10)])
      ..done = true;

    final back = Reply.fromJson(reply.toJson());

    expect(back.citations, hasLength(1));
    expect(back.citations.single.url.host, 'a.test');
    expect(back.citations.single.end, 10,
        reason: 'without the offset the marker cannot be placed again');
  });

  test('a reply with no sources stores no key for them', () {
    expect(Reply().toJson().containsKey('citations'), isFalse);
  });

  test('a stored source with an unreadable url is dropped, not restored', () {
    // The alternative is a rail row that opens nothing.
    final back = Reply.fromJson({
      'role': 'reply',
      'text': 'hi',
      'citations': [
        {'title': 'broken', 'url': 'not a url'},
        {'title': 'fine', 'url': 'https://b.test/a'},
      ],
    });

    expect(back.citations, hasLength(1));
    expect(back.citations.single.url.host, 'b.test');
  });

  test('a restored reply is never left mid-search', () {
    // `searching` is live state. Restoring it true would spin a progress
    // indicator forever for a search that finished days ago.
    final reply = Reply()
      ..write('done')
      ..searching = true
      ..done = true;

    expect(Reply.fromJson(reply.toJson()).searching, isFalse);
  });

  test('citations survive alongside an artifact and images', () {
    // They are stored on the same reply, and a `toJson` that dropped one when
    // another was present would be found only by someone reloading.
    final reply = Reply()
      ..write('page and sources')
      ..artifactId = 'art-1'
      ..imageIds.add('img-1')
      ..citations.add(source('c.test'))
      ..done = true;

    final back = Reply.fromJson(reply.toJson());

    expect(back.artifactId, 'art-1');
    expect(back.imageIds, ['img-1']);
    expect(back.citations, hasLength(1));
  });
}
