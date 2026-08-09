import 'package:flutter/material.dart';

/// The six places the app can be.
///
/// **Modes are workspaces, not routers.** Every mode can produce everything —
/// ask for a landing page in Notes and you get a landing page. What a mode
/// chooses is the *surface*: what is on screen, what is at hand, what the
/// defaults are. The engine behind all six is the same.
///
/// This matters most for the default. [chat] has to answer anything at all,
/// because that is the promise: ask for whatever you want and get it back.
/// A mode that could only chat would push people into picking a mode before
/// they had finished having the thought.
enum AppMode {
  /// The default, and the one that has to be able to do everything.
  chat,

  /// A repository. An IDE on a desktop or tablet, a task list on a phone.
  code,

  /// Images, and the conversation that edits them.
  visual,

  /// Designed documents — pages, decks, posters — where looking good is the
  /// acceptance criterion.
  design,

  /// A folder of files and a long task the app works through on its own.
  work,

  /// Your voice, turned into clean text you can keep.
  notes;

  String get label => switch (this) {
        AppMode.chat => 'Chat',
        AppMode.code => 'Code',
        AppMode.visual => 'Visual',
        AppMode.design => 'Design',
        AppMode.work => 'Work',
        AppMode.notes => 'Notes',
      };

  /// The rail is narrow, so these are outline-weight and visually simple —
  /// an icon that needs to be studied is not doing its job at 22px.
  IconData get icon => switch (this) {
        AppMode.chat => Icons.forum_outlined,
        AppMode.code => Icons.terminal_rounded,
        AppMode.visual => Icons.auto_awesome_outlined,
        AppMode.design => Icons.brush_outlined,
        AppMode.work => Icons.inventory_2_outlined,
        AppMode.notes => Icons.mic_none_rounded,
      };

  IconData get activeIcon => switch (this) {
        AppMode.chat => Icons.forum_rounded,
        AppMode.code => Icons.terminal_rounded,
        AppMode.visual => Icons.auto_awesome,
        AppMode.design => Icons.brush_rounded,
        AppMode.work => Icons.inventory_2_rounded,
        AppMode.notes => Icons.mic_rounded,
      };

  /// One line, shown in the empty state. Says what the mode is *for*, not what
  /// it contains — someone opening Work for the first time needs to know why
  /// they would.
  String get blurb => switch (this) {
        AppMode.chat =>
          'Ask for anything — an answer, a picture, a page, a plan — and get it back.',
        AppMode.code =>
          'Point it at a repository and describe the change. Review the diff before it lands.',
        AppMode.visual =>
          'Make an image, then talk to it: change the light, swap the background, try it wider.',
        AppMode.design =>
          'Pages, decks and posters that come out looking designed rather than generated.',
        AppMode.work =>
          'Hand over a folder and a job. It works through it and brings back the files.',
        AppMode.notes =>
          'Talk. It writes down what you meant, without the ums.',
      };
}
