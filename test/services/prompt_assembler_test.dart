import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/project.dart';
import 'package:shift_ai/data/stores/styles_store.dart';
import 'package:shift_ai/turn/prompt_assembler.dart';

/// The instructions a built-in style carries, the way the composer resolves
/// them — built-ins and custom styles go through the same lookup now.
String _style(String id) =>
    builtInStyles.firstWhere((s) => s.id == id).instructions;

void main() {
  group('assembleSystemPrompt', () {
    test('bare prompt has only the base persona', () {
      final prompt = assembleSystemPrompt();
      expect(prompt, contains('You are SHIFT AI'));
      expect(prompt.contains('Address the user'), isFalse);
      expect(prompt.contains('Active project'), isFalse);
      expect(prompt.contains('standing instructions'), isFalse);
    });

    test('nickname, style, and instructions each layer in', () {
      final prompt = assembleSystemPrompt(
        nickname: 'Nate',
        styleInstruction: _style('concise'),
        customInstructions: 'Always use metric units.',
      );
      expect(prompt, contains('Address the user as "Nate"'));
      expect(prompt, contains('short and direct'));
      expect(prompt, contains('Always use metric units.'));
    });

    test('Normal adds no style clause — it is the absence of a style', () {
      final prompt = assembleSystemPrompt(styleInstruction: _style('normal'));
      expect(prompt.contains('\n\nStyle:'), isFalse);
      expect(prompt.contains('short and direct'), isFalse);
      expect(prompt.contains('thorough'), isFalse);
    });

    test('role, traits, named styles, and memories each layer in', () {
      final prompt = assembleSystemPrompt(
        role: 'product designer',
        traits: 'direct and encouraging',
        styleInstruction: _style('formal'),
        memories: ['Prefers TypeScript', 'Lives in Kyoto'],
      );
      expect(prompt, contains('product designer'));
      expect(prompt, contains('direct and encouraging'));
      expect(prompt, contains('polished, professional register'));
      expect(prompt, contains('Prefers TypeScript'));
      expect(prompt, contains('Lives in Kyoto'));
    });

    test('explanatory style asks for teaching depth', () {
      final prompt = assembleSystemPrompt(styleInstruction: _style('explanatory'));
      expect(prompt, contains('teach'));
    });

    test('project instructions and knowledge are included', () {
      final prompt = assembleSystemPrompt(
        project: const Project(
          id: 'p1',
          name: 'Bakery brand',
          customInstructions: 'Speak like a warm pastry chef.',
          knowledge: [
            KnowledgeDoc(name: 'Brand voice', text: 'Buttery. Golden.'),
          ],
        ),
      );
      expect(prompt, contains('Active project: "Bakery brand"'));
      expect(prompt, contains('Speak like a warm pastry chef.'));
      expect(prompt, contains('--- Brand voice ---'));
      expect(prompt, contains('Buttery. Golden.'));
    });

    test('knowledge beyond the character budget is truncated', () {
      final bigDoc = 'x' * (knowledgeCharBudget + 500);
      final prompt = assembleSystemPrompt(
        project: Project(
          id: 'p1',
          name: 'Big',
          knowledge: [
            KnowledgeDoc(name: 'Huge', text: bigDoc),
            const KnowledgeDoc(name: 'After', text: 'never fits'),
          ],
        ),
      );
      expect(prompt.contains('never fits'), isFalse);
      expect(prompt, contains('omitted for length'));
      // The included portion is capped near the budget, not the full doc.
      expect(prompt.length, lessThan(knowledgeCharBudget + 2000));
    });
  });

  group('systemPromptForCodeTurn', () {
    test('leaves a non-code turn untouched', () {
      expect(systemPromptForCodeTurn('base', isCode: false), 'base');
      expect(systemPromptForCodeTurn(null, isCode: false), isNull);
    });

    test('appends the artifact instruction on a code turn', () {
      final out = systemPromptForCodeTurn('base', isCode: true)!;
      expect(out, startsWith('base'));
      expect(out, contains(codeArtifactInstruction));
    });

    test('still instructs when there is no personalization', () {
      // A turn with no nickname/project/style has an empty prompt, and the
      // instruction matters most there.
      expect(systemPromptForCodeTurn(null, isCode: true), codeArtifactInstruction);
      expect(systemPromptForCodeTurn('   ', isCode: true), codeArtifactInstruction);
    });
  });
}
