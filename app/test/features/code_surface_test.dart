import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/palette.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/agent.dart';
import 'package:shift/data/agent_store.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/conversation_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/features/chat/turn_controller.dart';
import 'package:shift/features/code/agent_list_screen.dart';
import 'package:shift/features/code/agent_row.dart';
import 'package:shift/features/code/code_chrome.dart';
import 'package:shift/features/code/code_composer.dart';
import 'package:shift/features/code/code_surface.dart';
import 'package:shift/shell/app_shell.dart';
import 'package:shift/shell/mode.dart';
import 'package:shift/shell/shell_controller.dart';

/// Code mode's surface, against the reference screenshots.
void main() {
  late Directory dir;
  late AgentStore agents;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-code');
    agents = AgentStore(KvStore(path: '${dir.path}/s.json'));
    await agents.load();
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// The two rows from the reference screenshots.
  Future<void> seedInto(AgentStore agents) async {
    await agents.addWorkspace(const GitHubWorkspace(
    id: 'w1', name: 'Yoked-Church-Web-App', repo: 'n/Yoked-Church-Web-App'));
    await agents.save(Agent(
    id: 'a1',
    title: 'Apple aesthetic cesium 3D',
    workspaceId: 'w1',
    status: AgentStatus.needsAttention,
    diff: const DiffStat(added: 8807, removed: 22),
    checksPassed: true,
    updatedAt: DateTime(2026, 8, 10, 1),
    ));
    await agents.save(Agent(
    id: 'a2',
    title: 'Customizable church platform',
    workspaceId: 'w1',
    status: AgentStatus.failed,
    note: 'Unable To Complete Request',
    updatedAt: DateTime(2026, 8, 10, 2),
    ));
  }

  /// `runAsync`, because a widget test's zone fakes time and a real file write
  /// never completes inside it — the test hangs rather than failing.
  Future<void> seed(WidgetTester t) => t.runAsync(() => seedInto(agents));

  Widget shell(ShellController controller) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: controller),
          ChangeNotifierProvider.value(value: agents),
          ChangeNotifierProvider(create: (_) => ApiKeysStore(KvStore())),
          ChangeNotifierProvider(create: (_) => ConversationStore(KvStore())),
          ChangeNotifierProvider(create: (_) => TurnController()),
        ],
        child: MaterialApp(
          theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
          home: const AppShell(),
        ),
      );

  Future<ShellController> openCode(WidgetTester t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(393, 852);
    addTearDown(t.view.reset);

    final controller = ShellController()..openMode(AppMode.code);
    addTearDown(controller.dispose);
    await t.pumpWidget(shell(controller));
    await t.pumpAndSettle();
    return controller;
  }

  testWidgets('Code mode brings its own surface, and the shell goes with it',
      (t) async {
    // A black body under a cream top bar does not read as a mode with its own
    // character; it reads as a rendering fault. The swap is at the frame, not
    // inside the mode.
    await openCode(t);

    final context = t.element(find.byType(CodeSurface));
    expect(context.colors.ground, ShiftColors.code.ground);

    final scaffold = t.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, ShiftColors.code.ground);
  });

  testWidgets('a pushed screen keeps the surface', (t) async {
    // The failure this guards against is invisible until you tap something on
    // a device: a pushed route is built by the app's Navigator, which sits
    // *above* the theme the shell wraps Code mode in.
    await openCode(t);
    await t.tap(find.text('Working'));
    await t.pumpAndSettle();

    expect(find.byType(AgentListScreen), findsOneWidget);
    final context = t.element(find.byType(AgentListScreen));
    expect(context.colors.ground, ShiftColors.code.ground);
  });

  testWidgets('the Inbox offers the four states and the workspaces',
      (t) async {
    await seed(t);
    await openCode(t);

    for (final label in [
      'All Agents',
      'Working',
      'Needs Attention',
      'In Review',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Yoked-Church-Web-App'), findsOneWidget);
    expect(find.text('Add Workspace'), findsOneWidget);
  });

  testWidgets('counts follow the label rather than sitting in a badge',
      (t) async {
    await seed(t);
    await openCode(t);

    // One needing attention; Working and In Review are both empty — which is
    // two zeros, not one. Asserted per card rather than by counting glyphs.
    expect(
      find.descendant(
        of: find.ancestor(
            of: find.text('Needs Attention'), matching: find.byType(Row)).first,
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(find.text('0'), findsNWidgets(2));
  });

  testWidgets('an empty state says what would appear there', (t) async {
    await openCode(t);
    await t.tap(find.text('Working'));
    await t.pumpAndSettle();

    expect(find.text('Agents that are actively working appear here'),
        findsOneWidget);
  });

  testWidgets('a failed run says what happened, not a diff of nothing',
      (t) async {
    await seed(t);
    await openCode(t);
    await t.tap(find.text('Yoked-Church-Web-App'));
    await t.pumpAndSettle();

    expect(find.text('Unable To Complete Request'), findsOneWidget);
    expect(find.textContaining('+0 -0'), findsNothing);
  });

  testWidgets('a diff is grouped so it can be sized at a glance', (t) async {
    await seed(t);
    await openCode(t);
    await t.tap(find.text('Yoked-Church-Web-App'));
    await t.pumpAndSettle();

    // `textContaining`, not `text`: the metadata is one span chain now, so the
    // whole line is not any single widget's `data`.
    expect(find.textContaining('+8,807 -22'), findsOneWidget);
  });

  testWidgets('the composer is on the lists too, not only inside an agent',
      (t) async {
    // It being permanent is the point: starting work never means navigating
    // somewhere first.
    await seed(t);
    await openCode(t);
    expect(find.text('Plan, ask, build…'), findsOneWidget);

    await t.tap(find.text('All Agents'));
    await t.pumpAndSettle();
    expect(find.text('Plan, ask, build…'), findsOneWidget);
  });

  testWidgets('every control clears the tap-target minimum', (t) async {
    await seed(t);
    await openCode(t);

    // Scoped to this mode's own controls. A blanket sweep of every `InkWell`
    // also catches the framework's internals, which makes the check fail for
    // reasons nobody here can act on.
    for (final finder in [
      find.byType(CodeCircleButton),
      find.byType(AgentRow),
      find.byType(CodeComposer),
    ]) {
      for (var i = 0; i < finder.evaluate().length; i++) {
        expect(t.getSize(finder.at(i)).height,
            greaterThanOrEqualTo(kMinTouchTarget),
            reason: '$finder $i');
      }
    }
  });

  group('the model', () {
    test('a diff is grouped in threes', () {
      expect('${const DiffStat(added: 8807, removed: 22)}', '+8,807 -22');
      expect('${const DiffStat(added: 53170, removed: 2)}', '+53,170 -2');
      expect('${const DiffStat()}', '+0 -0');
      expect(const DiffStat().isEmpty, isTrue);
    });

    test('checks not run is not the same as checks failed', () {
      // A green tick for "nobody has checked" would be a lie, and it is the
      // one piece of metadata people will trust without reading.
      final agent = Agent(
        id: 'a',
        title: 't',
        workspaceId: 'w',
        status: AgentStatus.working,
        updatedAt: DateTime(2026),
      );
      expect(agent.checksPassed, isNull);
    });

    test('removing a workspace takes its agents with it', () async {
      await seedInto(agents);
      await agents.removeWorkspace('w1');
      expect(agents.workspaces, isEmpty);
      expect(agents.agents, isEmpty,
          reason: 'rows pointing at a workspace that no longer exists read as '
              'the app having lost track');
    });

    test('a store nobody warmed up still reads what is on disk', () async {
      // Caught by a screenshot, not by a test: `main` built this store and
      // never called `load`, so Code mode showed an empty Inbox over a disk
      // with agents on it. Reading on demand makes that unmakeable.
      await seedInto(agents);

      // The app's actual shape: **one** KvStore shared by every store, warmed
      // once. The sibling stores then work whether or not each of them was
      // individually loaded — except this one, which cached at load and so
      // read empty. (A store with its own unloaded file genuinely cannot read
      // it synchronously; that is not the case being guarded.)
      final kv = KvStore(path: '${dir.path}/s.json');
      await kv.load();
      final never = AgentStore(kv);

      expect(never.agents, hasLength(2),
          reason: 'a store nobody called load() on must not read as empty');
      expect(never.workspaces, hasLength(1));
    });

    test('workspaces and agents survive a reload', () async {
      await seedInto(agents);
      final second = AgentStore(KvStore(path: '${dir.path}/s.json'));
      await second.load();

      expect(second.workspaces.single.name, 'Yoked-Church-Web-App');
      expect(second.agents, hasLength(2));
      expect(second.count(AgentStatus.needsAttention), 1);
    });
  });
}
