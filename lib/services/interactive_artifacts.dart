import 'dart:convert';

import '../models/artifact.dart';

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

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String renderRecipe(Recipe r, {String? heroImageDataUri}) {
    final ingredients = r.ingredients
        .map((i) =>
            '<li><label><input type="checkbox" class="ing"/> '
            '<span class="qty" data-base="${_esc(i.qty)}">${_esc(i.qty)}</span> '
            '<span>${_esc(i.item)}</span></label></li>')
        .join();
    final steps = r.steps
        .asMap()
        .entries
        .map((e) =>
            '<li><label><input type="checkbox" class="step"/> '
            '<span>${_esc(e.value)}</span></label></li>')
        .join();
    final hero = heroImageDataUri == null
        ? ''
        : '<img class="hero" src="$heroImageDataUri" alt="${_esc(r.title)}" />';
    return _page(r.title, '''
$hero
<h1>${_esc(r.title)}</h1>
<div class="meta">
  <span>⏱ <b id="mins">${r.minutes}</b> min</span>
  <span class="servings">🍽
    <button id="less" aria-label="fewer">−</button>
    <b id="serv">${r.servings}</b> servings
    <button id="more" aria-label="more">+</button>
  </span>
  <button id="timer" class="btn">Start timer</button>
  <span id="clock" class="clock"></span>
</div>
<h2>Ingredients <small id="ingprog"></small></h2>
<ul class="ings">$ingredients</ul>
<h2>Method <small id="stepprog"></small></h2>
<ol class="steps">$steps</ol>
<div class="row"><button class="btn" onclick="window.print()">Print</button>
<button class="btn ghost" id="reset">Reset</button></div>
''', '''
const base = ${r.servings};
function scale(n){
  document.getElementById('serv').textContent=n;
  document.querySelectorAll('.qty').forEach(q=>{
    const m=(q.dataset.base||'').match(/^([\\d./]+)(.*)\$/);
    if(!m) return; let val=eval(m[1].replace(/(\\d+)\\/(\\d+)/,'(\$1/\$2)'));
    if(isNaN(val)) return; const scaled=val*n/base;
    q.textContent=(Math.round(scaled*100)/100)+m[2];
  });
}
let serv=base;
document.getElementById('more').onclick=()=>scale(serv=Math.min(24,serv+1));
document.getElementById('less').onclick=()=>scale(serv=Math.max(1,serv-1));
function prog(sel,out){const b=[...document.querySelectorAll(sel)];
  const d=b.filter(x=>x.checked).length;
  document.getElementById(out).textContent=d+'/'+b.length;}
document.querySelectorAll('.ing').forEach(c=>c.onchange=()=>{prog('.ing','ingprog');
  c.closest('li').classList.toggle('done',c.checked);});
document.querySelectorAll('.step').forEach(c=>c.onchange=()=>{prog('.step','stepprog');
  c.closest('li').classList.toggle('done',c.checked);});
prog('.ing','ingprog');prog('.step','stepprog');
let t=null,left=${r.minutes}*60;
document.getElementById('timer').onclick=function(){
  if(t){clearInterval(t);t=null;this.textContent='Start timer';return;}
  this.textContent='Pause';
  t=setInterval(()=>{left--;const m=Math.floor(left/60),s=left%60;
    document.getElementById('clock').textContent=m+':'+String(s).padStart(2,'0');
    if(left<=0){clearInterval(t);t=null;document.getElementById('clock').textContent='Done!';}
  },1000);
};
document.getElementById('reset').onclick=()=>{document.querySelectorAll('input').forEach(c=>c.checked=false);
  document.querySelectorAll('li').forEach(l=>l.classList.remove('done'));
  prog('.ing','ingprog');prog('.step','stepprog');scale(serv=base);};
''');
  }

  static String renderQuiz(List<QuizQuestion> qs, String title) {
    final body = qs
        .asMap()
        .entries
        .map((e) {
          final opts = e.value.options
              .asMap()
              .entries
              .map((o) =>
                  '<label class="opt"><input type="radio" name="q${e.key}" '
                  'value="${o.key}"/> <span>${_esc(o.value)}</span></label>')
              .join();
          return '<div class="q" data-answer="${e.value.answerIndex}">'
              '<p class="qt">${e.key + 1}. ${_esc(e.value.question)}</p>$opts</div>';
        })
        .join();
    return _page(title, '''
<h1>${_esc(title)}</h1>
<div class="quiz">$body</div>
<div class="row"><button class="btn" id="check">Check answers</button>
<button class="btn ghost" id="retry">Try again</button></div>
<p id="score" class="score"></p>
''', '''
document.getElementById('check').onclick=()=>{
  let correct=0;const qs=[...document.querySelectorAll('.q')];
  qs.forEach(q=>{const a=+q.dataset.answer;const picked=q.querySelector('input:checked');
    q.querySelectorAll('.opt').forEach((o,i)=>{o.classList.remove('right','wrong');
      if(i==a)o.classList.add('right');});
    if(picked){if(+picked.value===a)correct++;else picked.closest('.opt').classList.add('wrong');}
  });
  document.getElementById('score').textContent='You scored '+correct+' / '+qs.length;
};
document.getElementById('retry').onclick=()=>{document.querySelectorAll('input').forEach(i=>i.checked=false);
  document.querySelectorAll('.opt').forEach(o=>o.classList.remove('right','wrong'));
  document.getElementById('score').textContent='';};
''');
  }

  static String renderFlashcards(List<Flashcard> cards, String title) {
    final data = jsonEncode(
        cards.map((c) => {'front': c.front, 'back': c.back}).toList());
    return _page(title, '''
<h1>${_esc(title)}</h1>
<div id="card" class="card"><div class="inner"><div class="front"></div>
<div class="back"></div></div></div>
<div class="row"><button class="btn ghost" id="prev">‹ Prev</button>
<span id="count" class="count"></span>
<button class="btn ghost" id="next">Next ›</button></div>
<p class="hint">Click the card to flip.</p>
''', '''
const cards=$data;let i=0,flipped=false;
const card=document.getElementById('card');
function show(){card.classList.toggle('flip',flipped);
  card.querySelector('.front').textContent=cards[i].front;
  card.querySelector('.back').textContent=cards[i].back;
  document.getElementById('count').textContent=(i+1)+' / '+cards.length;}
card.onclick=()=>{flipped=!flipped;card.classList.toggle('flip',flipped);};
document.getElementById('next').onclick=()=>{i=(i+1)%cards.length;flipped=false;show();};
document.getElementById('prev').onclick=()=>{i=(i-1+cards.length)%cards.length;flipped=false;show();};
show();
''');
  }

  static String renderChecklist(List<String> items, String title) {
    final li = items
        .map((s) =>
            '<li><label><input type="checkbox" class="it"/> '
            '<span>${_esc(s)}</span></label></li>')
        .join();
    return _page(title, '''
<h1>${_esc(title)}</h1>
<div class="bar"><div id="fill"></div></div>
<p id="prog" class="count"></p>
<ul class="check">$li</ul>
<div class="row"><input id="new" placeholder="Add an item…" />
<button class="btn" id="add">Add</button></div>
''', '''
function refresh(){const b=[...document.querySelectorAll('.it')];
  const d=b.filter(x=>x.checked).length;const pct=b.length?Math.round(d/b.length*100):0;
  document.getElementById('fill').style.width=pct+'%';
  document.getElementById('prog').textContent=d+' of '+b.length+' done';}
function wire(c){c.onchange=()=>{c.closest('li').classList.toggle('done',c.checked);refresh();};}
document.querySelectorAll('.it').forEach(wire);
document.getElementById('add').onclick=()=>{const v=document.getElementById('new').value.trim();
  if(!v)return;const li=document.createElement('li');
  li.innerHTML='<label><input type="checkbox" class="it"/> <span></span></label>';
  li.querySelector('span').textContent=v;document.querySelector('.check').appendChild(li);
  wire(li.querySelector('.it'));document.getElementById('new').value='';refresh();};
refresh();
''');
  }

  /// Shared self-contained HTML shell with the app's look.
  static String _page(String title, String body, String script) => '''
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>${_esc(title)}</title>
<style>
  :root{color-scheme:light}
  *{box-sizing:border-box}
  body{margin:0;font-family:system-ui,-apple-system,sans-serif;background:#F5F4EF;
       color:#1d1d1f;padding:24px;line-height:1.5}
  .wrap{max-width:640px;margin:0 auto;background:#fff;border-radius:20px;
        padding:28px 32px;box-shadow:0 1px 3px rgba(0,0,0,.08)}
  .hero{width:100%;border-radius:14px;margin-bottom:18px;display:block}
  h1{font-family:Georgia,serif;font-size:30px;margin:0 0 12px}
  h2{font-size:18px;margin:22px 0 8px}
  h2 small{color:#8a8a8e;font-weight:600;margin-left:6px}
  .meta{display:flex;flex-wrap:wrap;gap:16px;align-items:center;color:#3a3a3c;
        font-size:15px;margin-bottom:6px}
  .meta .servings button,.btn{border:none;border-radius:999px;cursor:pointer}
  .meta .servings button{width:26px;height:26px;background:#efeee9;font-size:16px}
  .btn{background:#AF52DE;color:#fff;padding:9px 18px;font-weight:600;font-size:14px}
  .btn.ghost{background:#efeee9;color:#1d1d1f}
  .clock{font-variant-numeric:tabular-nums;font-weight:700}
  ul,ol{padding-left:4px;list-style:none;margin:0}
  ol{counter-reset:s}
  ul li,ol li{padding:7px 0;border-bottom:1px solid #f0efe9}
  label{display:flex;gap:10px;align-items:flex-start;cursor:pointer}
  input[type=checkbox],input[type=radio]{margin-top:3px}
  li.done>label>span{text-decoration:line-through;color:#a0a0a5}
  .qty{font-weight:700;min-width:56px;display:inline-block}
  .row{display:flex;gap:10px;align-items:center;margin-top:18px;flex-wrap:wrap}
  .q{margin:14px 0;padding-bottom:8px;border-bottom:1px solid #f0efe9}
  .qt{font-weight:600;margin:0 0 8px}
  .opt{display:flex;gap:8px;padding:6px 10px;border-radius:10px;margin:3px 0}
  .opt.right{background:#e6f8ec}.opt.wrong{background:#fdeaea}
  .score{font-weight:700;font-size:17px;margin-top:12px}
  .card{perspective:1000px;height:220px;cursor:pointer;margin:8px 0}
  .card .inner{position:relative;width:100%;height:100%;transition:transform .5s;
    transform-style:preserve-3d}
  .card.flip .inner{transform:rotateY(180deg)}
  .card .front,.card .back{position:absolute;inset:0;backface-visibility:hidden;
    display:flex;align-items:center;justify-content:center;text-align:center;
    padding:24px;border-radius:16px;background:#efeee9;font-size:20px;font-weight:600}
  .card .back{transform:rotateY(180deg);background:#AF52DE;color:#fff}
  .count{color:#8a8a8e;font-weight:600}
  .hint{color:#a0a0a5;font-size:13px}
  .bar{height:8px;background:#efeee9;border-radius:99px;overflow:hidden;margin:8px 0}
  #fill{height:100%;width:0;background:#34C759;transition:width .3s}
  #new{flex:1;padding:9px 12px;border:1px solid #e2e1da;border-radius:10px;font-size:14px}
</style></head>
<body><div class="wrap">$body</div>
<script>$script</script></body></html>
''';

  /// Builds the interactive HTML into an artifact.
  static Artifact build({
    required InteractiveKind kind,
    required String conversationId,
    required String title,
    required String html,
  }) =>
      Artifact(
        id: _uuidLike(title),
        conversationId: conversationId,
        title: title,
        kind: ArtifactKind.html,
        versions: [ArtifactVersion(content: html, createdAt: DateTime.now())],
      );

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

  static String _uuidLike(String seedText) {
    final seed = seedText.codeUnits
        .fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);
    return 'interactive-${seed.toRadixString(16)}-${DateTime.now().microsecondsSinceEpoch}';
  }
}
