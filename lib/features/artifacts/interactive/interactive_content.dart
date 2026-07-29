import 'dart:convert';


/// The kinds of interactive artifact SHIFT AI can build — self-contained
/// HTML+CSS+JS widgets that run live in the artifact panel's sandboxed iframe,
/// the way Claude's recipe cards do.
enum InteractiveKind { recipe, quiz, flashcards, checklist }

extension InteractiveKindLabel on InteractiveKind {
  String get label => switch (this) {
        InteractiveKind.recipe => 'recipe card',
        InteractiveKind.quiz => 'quiz',
        InteractiveKind.flashcards => 'flashcards',
        InteractiveKind.checklist => 'checklist',
      };
}

// ---- Content models ----

class Recipe {
  final String title;
  final int servings;
  final int minutes;
  final List<({String qty, String item})> ingredients;
  final List<String> steps;
  const Recipe({
    required this.title,
    required this.servings,
    required this.minutes,
    required this.ingredients,
    required this.steps,
  });
}

class QuizQuestion {
  final String question;
  final List<String> options;
  final int answerIndex;
  const QuizQuestion(
      {required this.question, required this.options, required this.answerIndex});
}

class Flashcard {
  final String front;
  final String back;
  const Flashcard({required this.front, required this.back});
}

/// Everything the interactive-artifact system needs to know about a request.
class InteractiveArtifacts {
  InteractiveArtifacts._();

  static const _recipeKeywords = [
    'recipe card', 'recipe', 'how to cook', 'how to make', 'how do i make',
    'how do i cook', 'ingredients for',
  ];
  static const _quizKeywords = [
    'quiz', 'trivia', 'multiple choice', 'test my knowledge', 'quiz me',
  ];
  static const _flashcardKeywords = [
    'flashcard', 'flash card', 'study cards', 'study card', 'flashcards',
  ];
  static const _checklistKeywords = [
    'checklist', 'to-do list', 'todo list', 'to do list', 'packing list',
    'task list', 'shopping list',
  ];

  /// Detects an interactive-artifact request. Recipe/quiz/flashcards/checklist
  /// are checked with word cues so a generic "build a website" is unaffected.
  static InteractiveKind? detect(String input) {
    final lower = input.toLowerCase();
    if (_quizKeywords.any(lower.contains)) return InteractiveKind.quiz;
    if (_flashcardKeywords.any(lower.contains)) return InteractiveKind.flashcards;
    if (_checklistKeywords.any(lower.contains)) return InteractiveKind.checklist;
    if (_recipeKeywords.any(lower.contains)) return InteractiveKind.recipe;
    return null;
  }

  /// The topic/subject of an interactive request, with the command + kind words
  /// stripped.
  static String parseTopic(String input, InteractiveKind kind) {
    var s = input
        .replaceFirst(
            RegExp(
                r'^\s*(please\s+)?(can|could|would)?\s*(you\s+)?(please\s+)?'
                r'(make|build|create|generate|give\s+me|design)?\s*(me\s+)?'
                r'(?:(?:a|an|the)\s+)?(interactive\s+)?',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(
                r'\b(recipe\s*card|recipe|quiz|trivia|multiple\s*choice|'
                r'flash\s*cards?|study\s*cards?|checklist|to[\s-]*do\s*list|'
                r'packing\s*list|task\s*list|shopping\s*list|card|widget)\b',
                caseSensitive: false),
            ' ')
        .replaceFirst(
            RegExp(r'^\s*(about|on|for|of|to\s+make|to\s+cook)\s+',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.isEmpty) {
      s = switch (kind) {
        InteractiveKind.recipe => 'Chocolate Chip Cookies',
        InteractiveKind.quiz => 'General Knowledge',
        InteractiveKind.flashcards => 'Study Set',
        InteractiveKind.checklist => 'My List',
      };
    }
    return s;
  }

  // ---- Templated (offline) content ----

  static Recipe templatedRecipe(String topic) => Recipe(
        title: _title(topic),
        servings: 4,
        minutes: 35,
        ingredients: const [
          (qty: '2 cups', item: 'all-purpose flour'),
          (qty: '1 tsp', item: 'baking soda'),
          (qty: '1/2 tsp', item: 'salt'),
          (qty: '3/4 cup', item: 'butter, softened'),
          (qty: '3/4 cup', item: 'sugar'),
          (qty: '2', item: 'eggs'),
          (qty: '1 tsp', item: 'vanilla extract'),
        ],
        steps: [
          'Preheat the oven to 190°C (375°F) and line a tray with parchment.',
          'Whisk the flour, baking soda and salt in a bowl.',
          'Cream the butter and sugar, then beat in the eggs and vanilla.',
          'Fold the dry mix into the wet until just combined.',
          'Shape, space on the tray, and bake 10–12 minutes until golden.',
          'Cool on the tray for 5 minutes before moving to a rack.',
        ],
      );

  static List<QuizQuestion> templatedQuiz(String topic) => [
        QuizQuestion(
          question: 'What is this quiz about?',
          options: [topic, 'Something else', 'Nothing', 'Everything'],
          answerIndex: 0,
        ),
        const QuizQuestion(
          question: 'How many options does a good multiple-choice question have?',
          options: ['One', 'Two', 'Three to four', 'Ten'],
          answerIndex: 2,
        ),
        const QuizQuestion(
          question: 'Add an API key in Settings and SHIFT AI will…',
          options: [
            'Do nothing',
            'Write real questions for you',
            'Delete the quiz',
            'Turn off'
          ],
          answerIndex: 1,
        ),
      ];

  static List<Flashcard> templatedFlashcards(String topic) => [
        Flashcard(front: 'What is "$topic"?', back: 'A study set generated by SHIFT AI.'),
        const Flashcard(front: 'How do I flip a card?', back: 'Click it.'),
        const Flashcard(
            front: 'How do I get real cards?',
            back: 'Add an API key in Settings.'),
      ];

  static List<String> templatedChecklist(String topic) => [
        'First thing for ${_title(topic)}',
        'Second thing',
        'Third thing',
        'One more to be safe',
      ];

  // ---- JSON parsing (live content) ----

  static Recipe? parseRecipeJson(String reply, String topic) {
    try {
      final m = _decodeObject(reply);
      final ingredients = (m['ingredients'] as List)
          .map((e) => e is Map
              ? (qty: '${e['qty'] ?? ''}', item: '${e['item'] ?? ''}')
              : (qty: '', item: '$e'))
          .where((e) => e.item.isNotEmpty)
          .toList();
      final steps = (m['steps'] as List).map((e) => '$e').toList();
      if (ingredients.isEmpty || steps.isEmpty) return null;
      return Recipe(
        title: (m['title'] as String?)?.trim().isNotEmpty == true
            ? m['title'] as String
            : _title(topic),
        servings: (m['servings'] as num?)?.toInt() ?? 4,
        minutes: (m['minutes'] as num?)?.toInt() ?? 30,
        ingredients: ingredients,
        steps: steps,
      );
    } catch (_) {
      return null;
    }
  }

  static List<QuizQuestion>? parseQuizJson(String reply) {
    try {
      final list = _decodeList(reply);
      final questions = <QuizQuestion>[];
      for (final e in list) {
        final m = e as Map;
        final options = (m['options'] as List).map((o) => '$o').toList();
        final ans = (m['answerIndex'] as num?)?.toInt() ?? 0;
        final q = '${m['question'] ?? ''}'.trim();
        if (q.isEmpty || options.length < 2) continue;
        questions.add(QuizQuestion(
            question: q, options: options, answerIndex: ans.clamp(0, options.length - 1)));
      }
      return questions.isEmpty ? null : questions;
    } catch (_) {
      return null;
    }
  }

  static List<Flashcard>? parseFlashcardsJson(String reply) {
    try {
      final list = _decodeList(reply);
      final cards = <Flashcard>[];
      for (final e in list) {
        final m = e as Map;
        final front = '${m['front'] ?? ''}'.trim();
        final back = '${m['back'] ?? ''}'.trim();
        if (front.isEmpty) continue;
        cards.add(Flashcard(front: front, back: back));
      }
      return cards.isEmpty ? null : cards;
    } catch (_) {
      return null;
    }
  }

  static List<String>? parseChecklistJson(String reply) {
    try {
      final list = _decodeList(reply);
      final items = list.map((e) => '$e'.trim()).where((s) => s.isNotEmpty).toList();
      return items.isEmpty ? null : items;
    } catch (_) {
      return null;
    }
  }

  /// The strict-JSON content prompt for a live provider.
  static String contentPrompt(InteractiveKind kind, String topic) =>
      switch (kind) {
        InteractiveKind.recipe =>
          'Write a recipe for "$topic". Respond with ONLY minified JSON: '
              '{"title":string,"servings":number,"minutes":number,'
              '"ingredients":[{"qty":string,"item":string}],"steps":[string]}. '
              'No prose, no code fences.',
        InteractiveKind.quiz =>
          'Write a 5-question multiple-choice quiz about "$topic". Respond with '
              'ONLY a minified JSON array of {"question":string,"options":[4 '
              'strings],"answerIndex":number}. No prose, no code fences.',
        InteractiveKind.flashcards =>
          'Write 6 study flashcards about "$topic". Respond with ONLY a minified '
              'JSON array of {"front":string,"back":string}. No prose, no code '
              'fences.',
        InteractiveKind.checklist =>
          'Write a practical checklist for "$topic". Respond with ONLY a '
              'minified JSON array of short strings. No prose, no code fences.',
      };

  // ---- HTML renderers (self-contained, interactive) ----


  static String _title(String s) => s.isEmpty
      ? s
      : s
          .split(' ')
          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
          .join(' ');

  static Map<String, dynamic> _decodeObject(String reply) {
    final cleaned = reply.replaceAll(RegExp(r'```(json)?'), '').trim();
    return jsonDecode(cleaned) as Map<String, dynamic>;
  }

  static List<dynamic> _decodeList(String reply) {
    final cleaned = reply.replaceAll(RegExp(r'```(json)?'), '').trim();
    return jsonDecode(cleaned) as List<dynamic>;
  }
}

/// Escapes text for interpolation into the artifacts' HTML.
/// Shared by the content builders and the renderers.
String escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
