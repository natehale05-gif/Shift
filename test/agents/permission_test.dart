import 'package:flutter_test/flutter_test.dart';
import 'package:shift/agents/permission.dart';
import 'package:shift/agents/tools.dart';

/// What the agent may do without asking.
///
/// The largest test block in the mode, because this is the file that makes a
/// shell over somebody's own documents defensible. Everything here is pure, so
/// there is nothing to fake and no excuse for thin coverage.
void main() {
  group('reads are never asked', () {
    test('under every mode', () {
      // Asking about these would be most of the prompts somebody sees, none of
      // them consequential — which is how you train the habit of approving
      // without reading, and that habit is what makes the one prompt that
      // matters useless.
      for (final mode in PermissionMode.values) {
        for (final tool in ['read_file', 'glob', 'grep']) {
          expect(decide(mode, tool, {'path': 'notes.md'}), isA<Allowed>(),
              reason: '${mode.name}/$tool');
        }
      }
    });
  });

  group('a command', () {
    test('asks under ask', () {
      final d = decide(PermissionMode.ask, 'run',
          {'command': 'pandoc', 'args': ['a.md', '-o', 'a.html']});
      expect(d, isA<NeedsApproval>());
    });

    test('asks under acceptEdits too, because it is not an edit', () {
      // The name is the argument. A mode called "accept edits" that quietly
      // included a shell would be the most expensive kind of surprise.
      expect(decide(PermissionMode.acceptEdits, 'run', {'command': 'rm'}),
          isA<NeedsApproval>());
    });

    test('goes through under dontAsk', () {
      expect(decide(PermissionMode.dontAsk, 'run', {'command': 'ls'}),
          isA<Allowed>());
    });

    test('the question names the command, not the tool', () {
      // "Allow run?" is not a question anybody can answer.
      final d = decide(PermissionMode.ask, 'run',
          {'command': 'rm', 'args': ['-rf', 'drafts']}) as NeedsApproval;
      expect(d.question, contains('rm -rf drafts'));
    });

    test('a command with no name still produces an answerable question', () {
      final d = decide(PermissionMode.ask, 'run', const {}) as NeedsApproval;
      expect(d.question, isNotEmpty);
    });
  });

  group('a write', () {
    test('asks under ask, and names the file', () {
      final d = decide(PermissionMode.ask, 'write_file',
          {'path': 'reports/q3.md'}) as NeedsApproval;
      expect(d.question, contains('reports/q3.md'));
    });

    test('an edit says edit, because replacing and changing differ', () {
      final d = decide(PermissionMode.ask, 'edit_file',
          {'path': 'reports/q3.md'}) as NeedsApproval;
      expect(d.question.toLowerCase(), contains('edit'));
    });

    test('goes through under acceptEdits and dontAsk', () {
      for (final mode in [PermissionMode.acceptEdits, PermissionMode.dontAsk]) {
        expect(decide(mode, 'write_file', {'path': 'a.md'}), isA<Allowed>(),
            reason: mode.name);
      }
    });
  });

  group('outside the folder', () {
    test('is refused, never asked', () {
      // Offering it as a question would let somebody approve their way out of
      // containment. There is nothing to weigh here.
      for (final path in [
        '../secrets.txt',
        '../../.ssh/id_rsa',
        '/etc/passwd',
        r'C:\Windows\system32',
        r'drafts\..\..\keys',
      ]) {
        for (final mode in PermissionMode.values) {
          expect(decide(mode, 'write_file', {'path': path}), isA<Refused>(),
              reason: '${mode.name}: $path');
        }
      }
    });

    test('refused even for a read', () {
      expect(decide(PermissionMode.dontAsk, 'read_file',
          {'path': '../../.ssh/id_rsa'}), isA<Refused>());
    });

    test('an ordinary nested path is fine', () {
      // The control. Without it, "refuse everything" would pass every
      // assertion above.
      expect(
          decide(PermissionMode.dontAsk, 'read_file',
              {'path': 'reports/2026/q3.md'}),
          isA<Allowed>());
    });
  });

  group('the whole tool set is decided', () {
    test('every tool has an answer under every mode', () {
      // A tool added without a decision would fall through to whatever the
      // last branch happens to be. This makes that a failing test rather than
      // a discovery.
      for (final tool in kWorkTools) {
        for (final mode in PermissionMode.values) {
          expect(decide(mode, tool.name, const {'path': 'a.md'}),
              isA<Decision>(),
              reason: '${mode.name}/${tool.name}');
        }
      }
    });

    test('something unrecognised is treated as a change, not waved through',
        () {
      // The safe fallthrough: an unknown name is assumed to do something.
      expect(decide(PermissionMode.ask, 'launch_missiles', const {}),
          isA<NeedsApproval>());
    });
  });

  group('the mode itself', () {
    test('an unreadable stored value reads as the careful one', () {
      // Defaulting the other way would let a corrupt setting silently hand
      // over a shell.
      expect(PermissionMode.fromName(null), PermissionMode.ask);
      expect(PermissionMode.fromName('whatever'), PermissionMode.ask);
      expect(PermissionMode.fromName('dontAsk'), PermissionMode.dontAsk);
    });

    test('every mode says what it means', () {
      for (final mode in PermissionMode.values) {
        expect(mode.label, isNotEmpty, reason: mode.name);
        expect(mode.blurb, isNotEmpty, reason: mode.name);
      }
    });
  });
}
