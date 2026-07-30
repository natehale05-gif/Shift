/// The line that opens a new chat.
///
/// Replaces a fixed headline and a row of canned prompts. The prompts were
/// demo scaffolding: they wrote a message *for* you, which is a strange thing
/// for a blank page to do, and they were the same four every time — so on the
/// second visit they were noise, and on a phone they pushed the composer
/// below the fold.
///
/// Pure so the rotation is provable without rendering anything: given the
/// same clock, name, seed and [avoid], the same greeting comes back.
library;

/// Greets by time of day, using [name] when the user has told us one.
///
/// [seed] chooses among the variants for that time of day. Callers should
/// derive it from something stable for the chat — not from the frame — or the
/// greeting will change while the user is reading it.
///
/// [avoid] is the greeting shown last time. It is skipped, so opening two new
/// chats in a row never shows the same line twice — the thing that made a
/// random pick feel broken rather than varied. Matching is done on the line
/// alone, before [name] is appended, so it survives the user setting or
/// changing their nickname.
String greetingFor({
  required DateTime now,
  String? name,
  int seed = 0,
  String? avoid,
}) {
  final all = _variantsFor(now.hour);
  // If avoiding the last line would leave nothing — a band with one variant,
  // or a stored value that is somehow every entry — fall back to the full set
  // rather than returning nothing at all.
  final pool = [for (final line in all) if (line != avoid) line];
  final variants = pool.isEmpty ? all : pool;
  final line = variants[seed.abs() % variants.length];
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty) return line;
  return '$line, $trimmed';
}

/// The chosen line *without* the name — what gets stored as "shown last time".
///
/// Same arguments as [greetingFor] minus the name, so it returns exactly the
/// variant that call picked. Derived this way rather than by splitting the
/// rendered string on its last comma: a greeting that contains a comma of its
/// own ("Winding down, or just starting") would be stored truncated, and would
/// then never match — silently disabling the avoidance for that one line.
String greetingLineFor({
  required DateTime now,
  int seed = 0,
  String? avoid,
}) =>
    greetingFor(now: now, seed: seed, avoid: avoid);

/// Bands chosen to match how people actually describe the day rather than
/// splitting it into equal quarters: "morning" runs to noon, "evening" starts
/// when the working day ends, and the small hours get their own gentler set
/// instead of being called evening.
List<String> _variantsFor(int hour) {
  if (hour >= 5 && hour < 12) return morningVariants;
  if (hour >= 12 && hour < 17) return afternoonVariants;
  if (hour >= 17 && hour < 22) return eveningVariants;
  return lateVariants;
}

/// The four bands, exposed so a test can check that a line naming a time of
/// day only ever appears in the band it names.
///
/// That guard exists because the small-hours set used to include "Good
/// evening" — so a chat opened at two in the morning was greeted as if it were
/// seven at night. One wrong line in one list is easy to miss by reading;
/// asserting the rule catches the next one too.
const List<String> morningVariants = [
  'Good morning',
  'Morning',
  'Ready when you are',
  "Let's make something",
  'Fresh start',
  'What are we making today',
  'Early start',
  'The day is wide open',
  'First thing on the list',
  'Where do we begin',
  'Coffee first, then what',
  'Something new',
  'Bright and early',
  'Top of the morning',
  'A clean page',
  'What is first',
  'Off we go',
  'Nothing built yet',
  'The good hours',
  'Say the word',
];

const List<String> afternoonVariants = [
  'Good afternoon',
  'Afternoon',
  'What are we building',
  'Ready when you are',
  "Let's pick up where we left off",
  'Halfway through',
  'What needs making',
  'Back at it',
  'Plenty of day left',
  'What can I help with',
  'Something to build',
  'Where to next',
  'Mid-day, mid-thought',
  'Straight to it',
  'What is on the list',
  'The long stretch',
  'Room for one more',
  'Pick a thread',
  'Still plenty of runway',
  'What are we solving',
];

const List<String> eveningVariants = [
  'Good evening',
  'Evening',
  'What are we making tonight',
  'Ready when you are',
  'Winding down, or just starting',
  'One more thing',
  'What can I help with',
  "Let's finish something",
  'The quiet part of the day',
  'Still something to make',
  'Evening shift',
  'What is on your mind',
  'Lights on, work out',
  'The unhurried hours',
  'Something before bed',
  'Last of the day',
  'What did today leave undone',
  'Time enough for one',
  'Tonight, then',
  'Take your time',
];

const List<String> lateVariants = [
  'Still up',
  'Working late',
  'Ready when you are',
  'Burning the midnight oil',
  'The quiet hours',
  'Late one tonight',
  'Nobody else is awake',
  'What are we making at this hour',
  'No rush',
  'Just us',
  'Still going',
  'The world is asleep',
  'Small hours, big ideas',
  'Nothing but time',
  'One more before bed',
  'Wide awake',
  'The night shift',
  'Nobody is waiting on this',
  'Quiet enough to think',
  'Whenever you are ready',
];
