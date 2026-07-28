


/// Pure helpers for the ShortReels studio: parse the topic + count, build the
/// scripts prompt, parse the model's JSON, provide a templated fallback, render
/// an HTML storyboard, and zip the pack (posters + scripts + storyboard).
import '../../../data/models/studio_result.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

class ShortReelsService {
  ShortReelsService._();

  static const defaultCount = 3;

  static ({String topic, int count}) parseReelsRequest(String input) {
    final countMatch = RegExp(r'(\d+)\s*(reels?|shorts?|videos?|clips?)',
            caseSensitive: false)
        .firstMatch(input);
    final count =
        (countMatch != null ? int.parse(countMatch.group(1)!) : defaultCount)
            .clamp(1, 8);

    var topic = input
        // Remove "<n> reels/shorts/…" and the bare studio nouns anywhere.
        .replaceAll(
            RegExp(r'\d+\s*(reels?|shorts?|videos?|clips?)',
                caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(
                r'\b(short[\s-]*form|shortreels|short\s*reels|reels\s*pack|'
                r'reels|shorts|tiktoks?|pack)\b',
                caseSensitive: false),
            ' ')
        // Strip a leading command verb + filler.
        .replaceFirst(
            RegExp(
                r'^\s*(please\s+)?(can\s+|could\s+|would\s+)?(you\s+)?'
                r'(please\s+)?(make|build|create|generate|cut|produce|'
                r'give\s+me|design|put\s+together)?\s*(me\s+)?'
                r'(?:(?:a|an|the)\s+)?(of\s+)?',
                caseSensitive: false),
            '')
        // Strip a leading connector.
        .replaceFirst(RegExp(r'^\s*(about|on|for|of)\s+', caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (topic.isEmpty) topic = 'Your Topic';
    return (topic: topic, count: count);
  }

  static String scriptsPrompt(String topic, int count) =>
      'Write $count short-form video reels (TikTok/Reels style) about "$topic". '
      'Respond with ONLY a minified JSON array of exactly $count objects, each '
      '{"hook": string (a punchy 1-line opener), "script": string (3-5 short '
      'shot-by-shot lines with VO)}. No prose, no code fences.';

  static int seedFor(String s) => s.codeUnits.fold<int>(
        7,
        (acc, c) => (acc * 31 + c) & 0x7fffffff,
      );

  static ShortReelsPackResult? parsePackJson(String reply, String topic) {
    try {
      final cleaned = reply.replaceAll(RegExp(r'```(json)?'), '').trim();
      final decoded = jsonDecode(cleaned) as List<dynamic>;
      final reels = <ShortReel>[];
      for (var i = 0; i < decoded.length; i++) {
        final m = decoded[i] as Map<String, dynamic>;
        final hook = (m['hook'] as String?)?.trim() ?? '';
        if (hook.isEmpty) continue;
        reels.add(ShortReel(
          hook: hook,
          script: (m['script'] as String?)?.trim() ?? '',
          seed: seedFor('$topic-$i-$hook'),
        ));
      }
      if (reels.isEmpty) return null;
      return ShortReelsPackResult(topic: topic, reels: reels, live: true);
    } catch (_) {
      return null;
    }
  }

  static ShortReelsPackResult templatedPack(String topic, int count) {
    const angles = [
      ('The 3-second hook that stops the scroll', 'POV: you just found TOPIC'),
      ('Nobody talks about this TOPIC trick', 'Here\'s what changed everything'),
      ('Do this before you try TOPIC', 'Save this for later'),
      ('TOPIC, but make it effortless', 'The one thing that matters'),
      ('I tried TOPIC for 7 days', 'Here\'s what happened'),
    ];
    final reels = <ShortReel>[
      for (var i = 0; i < count; i++)
        ShortReel(
          hook: angles[i % angles.length].$1.replaceAll('TOPIC', topic),
          script: '[Shot 1] ${angles[i % angles.length].$2.replaceAll('TOPIC', topic)}\n'
              '[Shot 2] VO: Quick, punchy, and honest about $topic.\n'
              '[Shot 3] VO: Here\'s the payoff.\n'
              '[Shot 4] CTA: Follow for more.',
          seed: seedFor('$topic-$i'),
        ),
    ];
    return ShortReelsPackResult(topic: topic, reels: reels, live: false);
  }

  static String storyboardHtml(
      ShortReelsPackResult pack, List<Uint8List> posters) {
    String esc(String s) =>
        s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    final cards = <String>[];
    for (var i = 0; i < pack.reels.length; i++) {
      final r = pack.reels[i];
      final img = i < posters.length
          ? '<img src="data:image/png;base64,${base64Encode(posters[i])}" '
              'alt="Reel ${i + 1}" style="width:100%;aspect-ratio:9/16;'
              'object-fit:cover;border-radius:12px;" />'
          : '';
      cards.add('<div class="reel">$img<h3>${esc(r.hook)}</h3>'
          '<pre>${esc(r.script)}</pre></div>');
    }
    return '''
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>${esc(pack.topic)} — reels</title>
<style>
  body { margin:0; font-family:system-ui,sans-serif; background:#F5F4EF; color:#1d1d1f; padding:24px; }
  h1 { font-family:Georgia,serif; }
  .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(240px,1fr)); gap:20px; }
  .reel { background:#fff; border-radius:16px; padding:16px; box-shadow:0 1px 3px rgba(0,0,0,.08); }
  .reel h3 { font-size:16px; margin:12px 0 8px; }
  .reel pre { white-space:pre-wrap; font:13px/1.5 system-ui; color:#3a3a3c; margin:0; }
</style></head>
<body><h1>${esc(pack.topic)} — short-form pack</h1>
<div class="grid">${cards.join()}</div></body></html>
''';
  }

  /// Zips the pack: one poster PNG per reel, a scripts.md, and storyboard.html.
  static Uint8List buildZip(
      ShortReelsPackResult pack, List<Uint8List> posters) {
    final archive = Archive();
    void addText(String path, String text) {
      final bytes = utf8.encode(text);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    final folder = _slug(pack.topic);
    for (var i = 0; i < posters.length; i++) {
      archive.addFile(ArchiveFile(
          '$folder/reel_${i + 1}_poster.png', posters[i].length, posters[i]));
    }
    final scripts = pack.reels
        .asMap()
        .entries
        .map((e) => '## Reel ${e.key + 1}\n\n**Hook:** ${e.value.hook}\n\n'
            '${e.value.script}\n')
        .join('\n');
    addText('$folder/scripts.md', '# ${pack.topic} — reel scripts\n\n$scripts');
    addText('$folder/storyboard.html', storyboardHtml(pack, posters));

    final zip = ZipEncoder().encode(archive) ?? const <int>[];
    return Uint8List.fromList(zip);
  }

  static String _slug(String s) {
    final words = s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(4);
    final joined = words.join('-');
    return joined.isEmpty ? 'reels' : joined;
  }
}
