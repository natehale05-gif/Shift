/// The line that opens a new chat.
///
/// Replaces a fixed headline and a row of canned prompts. The prompts were
/// demo scaffolding: they wrote a message *for* you, which is a strange thing
/// for a blank page to do, and they were the same four every time — so on the
/// second visit they were noise, and on a phone they pushed the composer
/// below the fold.
///
/// Pure so the rotation is provable without rendering anything: given the
/// same clock, name and seed, the same greeting comes back.
library;

/// Greets by time of day, using [name] when the user has told us one.
///
/// [seed] chooses among the variants for that time of day. Callers should
/// derive it from something stable for the chat — not from the frame — or the
/// greeting will change while the user is reading it.
String greetingFor({
  required DateTime now,
  String? name,
  int seed = 0,
}) {
  final variants = _variantsFor(now.hour);
  final line = variants[seed.abs() % variants.length];
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return line;
  return '$line, $trimmed';
}

/// Bands chosen to match how people actually describe the day rather than
/// splitting it into equal quarters: "morning" runs to noon, "evening" starts
/// when the working day ends, and the small hours get their own gentler set
/// instead of being called evening.
List<String> _variantsFor(int hour) {
  if (hour >= 5 && hour < 12) {
    return const [
      'Good morning',
      'Morning',
      'Ready when you are',
      "Let's make something",
    ];
  }
  if (hour >= 12 && hour < 17) {
    return const [
      'Good afternoon',
      'Afternoon',
      'What are we building',
      'Ready when you are',
    ];
  }
  if (hour >= 17 && hour < 22) {
    return const [
      'Good evening',
      'Evening',
      'What are we making tonight',
      'Ready when you are',
    ];
  }
  return const [
    'Still up',
    'Working late',
    'Good evening',
    'Ready when you are',
  ];
}
