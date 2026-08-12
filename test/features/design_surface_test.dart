import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/artifact.dart';
import 'package:shift/data/artifact_store.dart';
import 'package:shift/data/conversation_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/features/artifacts/artifact_panel.dart';
import 'package:shift/features/design/design_surface.dart';
import 'package:shift/features/design/design_turns.dart';

/// Design mode's surface.
void main() {
  late Directory dir;
  late ArtifactStore artifacts;
  late ConversationStore conversations;
  late DesignTurns turns;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-design');
    final kv = KvStore(path: '${dir.path}/kv.json');
    await kv.load();
    final keys = ApiKeysStore(kv);
    await keys.load();
    conversations = ConversationStore(kv);
    await conversations.load();
    artifacts = ArtifactStore(kv);
    await artifacts.load();
    turns = DesignTurns(
        keys: keys, conversations: conversations, artifacts: artifacts);
  });
  tearDown(() async {
    turns.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<DesignTurns>.value(
      value: turns,
      child: MaterialApp(
        theme: shiftTheme(Brightness.light, TargetPlatform.linux),
        home: const Scaffold(body: DesignSurface()),
      ),
    ));
    await tester.pump();
  }

  testWidgets('an empty canvas says what the mode makes', (tester) async {
    await pump(tester);

    expect(find.textContaining('poster'), findsOneWidget);
    expect(find.byType(ArtifactPanel), findsNothing);
    expect(find.text('Describe what you want made'), findsOneWidget);
  });

  testWidgets('the design is the screen, not a panel beside one',
      (tester) async {
    // The one decision that makes this a mode rather than a chat: there is no
    // transcript here, and the thing being made fills the space a transcript
    // would have taken.
    turns.produced.add(Artifact(
      id: 'd1',
      conversationId: 'c1',
      title: 'Jazz night poster',
      kind: ArtifactKind.html,
      versions: [
        ArtifactVersion(content: '<html><body>x</body></html>',
            createdAt: DateTime(2026)),
      ],
    ));

    await pump(tester);

    expect(find.byType(ArtifactPanel), findsOneWidget);
    // No close button: closing a panel you cannot get back to would empty the
    // mode with nothing to say why.
    expect(find.byTooltip('Close'), findsNothing);
  });

  testWidgets('the composer asks for a change once there is something to change',
      (tester) async {
    turns.produced.add(Artifact(
      id: 'd1',
      conversationId: 'c1',
      title: 'Jazz night poster',
      kind: ArtifactKind.html,
      versions: [
        ArtifactVersion(content: '<html><body>x</body></html>',
            createdAt: DateTime(2026)),
      ],
    ));

    await pump(tester);

    expect(find.text('Say what to change'), findsOneWidget);
    expect(find.text('Describe what you want made'), findsNothing);
  });

  testWidgets('a failure is shown here, not left in a hidden transcript',
      (tester) async {
    // There is no key, so the turn fails at once, and its sentence lives on a
    // reply this surface never draws.
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'a poster for a jazz night');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(find.textContaining('Settings'), findsOneWidget);
  });

  testWidgets('a design is argued with, so its turns keep a conversation',
      (tester) async {
    // Unlike Visual: a picture is finished when it arrives, a design is not.
    // "Make the heading bigger" means nothing without what came before.
    expect(turns.conversations, isNotNull);
  });
}
