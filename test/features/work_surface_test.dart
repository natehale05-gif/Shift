import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/agents/agent_loop.dart';
import 'package:shift/agents/permission.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/palette.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/core/widgets/agent_composer.dart';
import 'package:shift/data/agent.dart';
import 'package:shift/data/agent_run_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/data/update_store.dart';
import 'package:shift/features/work/approval_card.dart';
import 'package:shift/features/work/task_list.dart';
import 'package:shift/features/work/work_runner.dart';
import 'package:shift/features/work/work_surface.dart';
import 'package:shift/shell/app_shell.dart';
import 'package:shift/shell/mode.dart';
import 'package:shift/shell/shell_controller.dart';

/// Work mode's surface: the app's own paper, a plan you can read, and an
/// approval nobody can miss.
void main() {
  late Directory dir;
  late KvStore kv;
  late WorkAgents folders;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-work-ui');
    kv = KvStore(path: '${dir.path}/kv.json');
    folders = WorkAgents(kv);
    await folders.load();
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> seed(WidgetTester t) => t.runAsync(() async {
        await folders.addWorkspace(LocalFolder(
          id: 'f1',
          name: 'my-documents',
          path: dir.path,
          permission: PermissionMode.acceptEdits,
        ));
        await folders.save(Agent(
          id: 'j1',
          title: 'Summary of the Q3 notes',
          workspaceId: 'f1',
          status: AgentStatus.needsAttention,
          updatedAt: DateTime(2026, 8, 10),
        ));
      });

  Widget shell(ShellController controller, Brightness brightness) =>
      MultiProvider(
        providers: [
          // The shell renders `UpdateBanner`, which reads this. Idle and never
          // loaded here, so it does no I/O and draws nothing.
          ChangeNotifierProvider(create: (_) => UpdateStore(KvStore())),
          ChangeNotifierProvider.value(value: controller),
          ChangeNotifierProvider.value(value: folders),
          ChangeNotifierProvider(
            create: (_) => WorkRunner(
              agents: folders,
              runs: AgentRunStore(kv, namespace: 'work'),
            ),
          ),
        ],
        child: MaterialApp(
          theme: shiftTheme(brightness, TargetPlatform.iOS),
          home: const _WorkOnly(),
        ),
      );

  Future<void> openWork(
    WidgetTester t, {
    Brightness brightness = Brightness.light,
  }) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(393, 852);
    addTearDown(t.view.reset);

    final controller = ShellController()..openMode(AppMode.work);
    addTearDown(controller.dispose);
    await t.pumpWidget(shell(controller, brightness));
    await t.pumpAndSettle();
  }

  testWidgets('it lists the folders, and what each one allows', (t) async {
    await seed(t);
    await openWork(t);

    expect(find.byType(WorkSurface), findsOneWidget);
    expect(find.text('my-documents'), findsOneWidget);
    // On the row, not behind a tap. What an agent may do to somebody's files
    // without asking is not a detail to go looking for.
    expect(find.text(PermissionMode.acceptEdits.label), findsOneWidget);
    expect(find.text('Add a folder'), findsOneWidget);
    expect(find.text('Summary of the Q3 notes'), findsOneWidget);
  });

  testWidgets('it is the app\'s paper, not Code\'s dark chrome', (t) async {
    // The user's decision, and the thing that would look most obviously wrong:
    // two of six modes rendering as a different app.
    await openWork(t);

    final context = t.element(find.byType(WorkSurface));
    expect(context.colors.ground, isNot(ShiftColors.code.ground));
  });

  testWidgets('both themes render it', (t) async {
    for (final brightness in Brightness.values) {
      await openWork(t, brightness: brightness);
      expect(find.byType(WorkSurface), findsOneWidget,
          reason: brightness.name);
    }
  });

  testWidgets('every control clears the touch minimum', (t) async {
    // This check has caught this app five times, most recently at 22pt.
    await seed(t);
    await openWork(t);

    for (final finder in [
      find.byType(AgentComposer),
      // Every tappable row in the list. Scoped to the list rather than every
      // `InkWell` on screen: the composer's circles are a 34pt *ring* inside a
      // 44pt target, so a blanket sweep measures the drawing and fails on a
      // control that is fine.
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(InkWell),
      ),
    ]) {
      expect(finder.evaluate(), isNotEmpty, reason: '$finder found nothing');
      for (var i = 0; i < finder.evaluate().length; i++) {
        expect(t.getSize(finder.at(i)).height,
            greaterThanOrEqualTo(kMinTouchTarget),
            reason: '$finder $i');
      }
    }
  });

  group('the plan', () {
    testWidgets('shows how far it got, and ticks what is done', (t) async {
      await t.pumpWidget(_wrap(const TaskList(tasks: [
        AgentTask('Read the notes', done: true),
        AgentTask('Write the summary'),
      ])));

      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.text('Read the notes'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
    });

    testWidgets('nothing planned draws nothing at all', (t) async {
      // A heading over no rows reads as a list that failed to load.
      await t.pumpWidget(_wrap(const TaskList(tasks: [])));

      expect(find.text('Plan'), findsNothing);
    });
  });

  group('the approval', () {
    testWidgets('names what it wants to do, and both answers are reachable',
        (t) async {
      bool? answered;
      await t.pumpWidget(_wrap(ApprovalCard(
        question: 'Run `pandoc notes.md -o notes.html`?',
        onAllow: () => answered = true,
        onDeny: () => answered = false,
      )));

      // The command, not the tool. "Allow run?" is not a question anybody can
      // answer.
      expect(find.textContaining('pandoc notes.md'), findsOneWidget);

      await t.tap(find.text("Don't allow"));
      expect(answered, isFalse);
      await t.tap(find.text('Allow'));
      expect(answered, isTrue);
    });

    testWidgets('its buttons fit on the narrowest phone', (t) async {
      // Two buttons and a long command name is exactly the shape that overflows
      // — and an approval whose buttons are off the screen is a job nobody can
      // unblock.
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(320, 640);
      addTearDown(t.view.reset);

      await t.pumpWidget(_wrap(ApprovalCard(
        question: 'Run `pandoc --standalone --toc reports/quarter-three.md`?',
        onAllow: () {},
        onDeny: () {},
      )));

      expect(t.takeException(), isNull);
      for (final label in ["Don't allow", 'Allow']) {
        expect(t.getSize(find.text(label)).height,
            greaterThan(0), reason: label);
      }
    });
  });
}

Widget _wrap(Widget child) => MaterialApp(
      theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// The shell, opened straight at Work.
///
/// The mode's own surface rather than the whole [AppShell], because Work is the
/// only mode here and building the rest would mean providing every other mode's
/// store to prove something about this one.
class _WorkOnly extends StatelessWidget {
  const _WorkOnly();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.colors.ground,
        body: const SafeArea(child: WorkSurface()),
      );
}
