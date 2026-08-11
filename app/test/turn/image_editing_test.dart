import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shift/providers/access.dart';
import 'package:shift/providers/clients/gemini_image.dart';
import 'package:shift/shell/mode.dart';
import 'package:shift/turn/capability.dart';
import 'package:shift/turn/executors/image_executor.dart';
import 'package:shift/turn/job_graph.dart';
import 'package:shift/turn/job_output.dart';
import 'package:shift/turn/plan_jobs.dart';
import 'package:shift/turn/turn_event.dart';
import 'package:shift/turn/turn_request.dart';

/// Changing a picture rather than making one.
void main() {
  group('the plan', () {
    test('carries the picture being changed', () {
      final graph = planJobs(const TurnRequest(
        input: 'make it night',
        mode: AppMode.visual,
        editingImage: 'img-7',
      ));

      final step = graph.steps.single;
      expect(step.needs, Capability.image);
      expect(step.editing, 'img-7');
    });

    test('an edit is still routed by the words, not by the selection', () {
      // The selection says *which* picture, never *what kind of job*. A
      // selected image that turned every request into an image job would make
      // "write me a caption for this" undoable without clearing it first.
      final graph = planJobs(const TurnRequest(
        input: 'write me a caption for this',
        mode: AppMode.visual,
        editingImage: 'img-7',
      ));

      expect(graph.steps.single.needs, Capability.text);
    });

    test('with nothing selected the step edits nothing', () {
      final graph = planJobs(
          const TurnRequest(input: 'a vase of tulips', mode: AppMode.visual));
      expect(graph.steps.single.editing, isNull);
    });
  });

  group('the request body', () {
    test('an edit sends the picture, and sends it before the instruction', () {
      // Order is not cosmetic: an instruction ahead of its subject reads as a
      // request for something new.
      final body = GeminiImage.buildBody('make it night',
          source: Uint8List.fromList([1, 2, 3]));

      final parts =
          (body['contents'] as List).first as Map<String, dynamic>;
      final list = parts['parts'] as List;
      expect(list.first, containsPair('inline_data', isA<Map>()));
      expect(list.last, containsPair('text', 'make it night'));

      final inline = (list.first as Map)['inline_data'] as Map;
      expect(base64Decode('${inline['data']}'), [1, 2, 3]);
      expect(inline['mime_type'], 'image/png');
    });

    test('a plain generation sends only the instruction', () {
      // The control. Without it the assertion above passes on a client that
      // always attaches something.
      final body = GeminiImage.buildBody('a vase of tulips');
      final parts = (body['contents'] as List).first as Map<String, dynamic>;
      expect((parts['parts'] as List).single, containsPair('text', isA<String>()));
    });
  });

  group('the executor', () {
    ImageExecutor executor({
      required Future<Uint8List?> Function(String) source,
      required http.Client Function() client,
    }) =>
        ImageExecutor(
          usable: (id) => id == 'gemini',
          access: (_) async => const DirectKey('k'),
          sourceBytes: source,
          gemini: GeminiImage(clientFactory: client),
        );

    const step = JobStep(
      id: 'image',
      needs: Capability.image,
      produces: OutputKind.image,
      instruction: 'make it night',
      label: 'Changing it',
      editing: 'img-7',
    );

    test('the picture reaches the provider', () async {
      Uint8List? sent;
      final events = await executor(
        source: (_) async => Uint8List.fromList([9, 9, 9]),
        client: () => _Records((body) {
          final parts = ((jsonDecode(body)['contents'] as List).first
              as Map<String, dynamic>)['parts'] as List;
          final inline = (parts.first as Map)['inline_data'] as Map?;
          if (inline != null) sent = base64Decode('${inline['data']}');
        }),
      ).run(step, const {}).toList();

      expect(sent, [9, 9, 9],
          reason: 'an edit that silently drops its source is a new picture');
      expect(events.whereType<StepCompleted>(), hasLength(1));
    });

    test('a picture that is gone refuses instead of making a new one',
        () async {
      // Someone who asked to change *this* picture and got an unrelated one
      // has been charged for the wrong thing and has to notice it themselves.
      var called = false;
      final events = await executor(
        source: (_) async => null,
        client: () => _Records((_) => called = true),
      ).run(step, const {}).toList();

      expect(called, isFalse, reason: 'and it costs nothing');
      final failed = events.whereType<StepFailed>().single;
      expect(failed.reason, contains('no longer on this device'));
    });
  });
}

/// A fake transport that hands the request body to [onBody] and answers with a
/// one-pixel picture.
class _Records extends http.BaseClient {
  final void Function(String body) onBody;

  _Records(this.onBody);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    onBody(utf8.decode(await request.finalize().toBytes()));
    final payload = jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'inlineData': {
                  'mimeType': 'image/png',
                  'data': base64Encode([1, 2, 3]),
                }
              }
            ]
          }
        }
      ]
    });
    return http.StreamedResponse(
      Stream.value(utf8.encode(payload)),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}
