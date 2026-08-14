import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shift/data/account_store.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/data/provider_access_source.dart';
import 'package:shift/providers/clients/openai_image.dart';
import 'package:shift/turn/capability.dart';
import 'package:shift/turn/executors/image_executor.dart';
import 'package:shift/turn/job_graph.dart';
import 'package:shift/turn/job_output.dart';
import 'package:shift/turn/job_runner.dart';
import 'package:shift/turn/turn_event.dart';

import '../data/provider_access_source_test.dart' show Host;

/// The reported failure, driven through the real executor and a real HTTP
/// client rather than asserted a layer up.
///
/// *"generate an image of a pink flower"* → **"No provider is set up for images
/// yet"**, with SHIFT's keys sitting on the server and a plan covering them.
/// The unit test above proves the source resolves it; this proves the step
/// actually runs, and — the part that matters for a metered product — that the
/// request goes to **the proxy** rather than to the provider with no key.
void main() {
  late Directory dir;
  late ApiKeysStore keys;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-managed');
    keys = ApiKeysStore(KvStore(path: '${dir.path}/settings.json'));
    await keys.load();
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  final graph = JobGraph.build([
    const JobStep(
      id: 'main',
      needs: Capability.image,
      produces: OutputKind.image,
      instruction: 'a pink flower',
      label: 'Drawing',
    ),
  ]).graph!;

  testWidgets('a plan pays for the picture, and the call goes to the proxy',
      (_) async {
    final account = AccountStore(backend: Host(covers: {'openai'}));
    await account.restore();
    await account.refresh();

    final asked = <Uri>[];
    final source = ProviderAccessSource(keys: keys, account: account);
    final events = await JobRunner({
      Capability.image: ImageExecutor(
        usable: source.usable,
        access: source.access,
        explainUnavailable: source.explain,
        openai: OpenAiImage(
          clientFactory: () => MockClient((request) async {
            asked.add(request.url);
            return http.Response(
              jsonEncode({
                'data': [
                  {'b64_json': base64Encode([137, 80, 78, 71])}
                ]
              }),
              200,
            );
          }),
        ),
      ),
    }).run(graph).toList();

    // The picture arrived...
    expect(events.whereType<StepCompleted>().single.output,
        isA<ImageOutput>());
    expect(events.whereType<StepFailed>(), isEmpty);

    // ...and it was bought with the plan, not sent to OpenAI directly. This is
    // the half that keeps the meter honest: a call that reached the provider
    // without going through the proxy is one nobody was charged for.
    expect(asked.single.path, contains('provider-proxy'));
    expect(asked.single.host, isNot(contains('openai.com')));
    expect(keys.has('openai'), isFalse, reason: 'no key on this device');
  });

  testWidgets('with no plan and no key it says which of the reasons it is',
      (_) async {
    // The sentence a member actually saw covered five states. Signed in with
    // no plan is one of them, and it is the one that used to read "add a key
    // in Settings, or start a plan" to somebody who had done neither and could
    // not tell which they were missing.
    final account = AccountStore(backend: Host(planned: false));
    await account.restore();
    await account.refresh();

    final source = ProviderAccessSource(keys: keys, account: account);
    final events = await JobRunner({
      Capability.image: ImageExecutor(
        usable: source.usable,
        access: source.access,
        explainUnavailable: source.explain,
      ),
    }).run(graph).toList();

    final failed = events.whereType<StepFailed>().single;
    expect(failed.reason, contains('do not have an active plan'));
    expect(failed.reason, contains('images'));
  });
}
