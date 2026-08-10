import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';

/// The box you type into.
///
/// Claude's shape, and each part of it is a decision rather than decoration:
///
/// * **One rounded box containing everything** — the field, the attach button,
///   the send button. Not a field with controls beside it, which is the
///   messaging-app shape and reads completely differently.
/// * **It grows with the text** to a ceiling, then scrolls. A single-line
///   input for something people paste paragraphs into is the most common way
///   this component is got wrong.
/// * **Send sits bottom-right inside the box**, enabled only when there is
///   something to send.
/// * **Enter sends; Shift-Enter is a newline** — on a desktop keyboard. On a
///   touch keyboard Enter must insert a newline, because there is no shift to
///   hold and no way to type a second paragraph otherwise.
class Composer extends StatefulWidget {
  final ValueChanged<String> onSend;
  final bool busy;
  final String hint;

  const Composer({
    super.key,
    required this.onSend,
    this.busy = false,
    this.hint = 'How can I help you today?',
  });

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.busy) return;
    _controller.clear();
    widget.onSend(text);
    // Focus is kept so a second message does not need a second tap. On a
    // phone this also keeps the keyboard up, which is what people expect
    // mid-conversation.
    _focus.requestFocus();
  }

  bool get _keyboardSends {
    // A hardware keyboard is assumed on desktop and not on touch. Getting this
    // backwards is unrecoverable for the user on a phone: Enter would send,
    // and a second paragraph would become impossible to type.
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.sm, Space.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CallbackShortcuts(
            bindings: {
              if (_keyboardSends)
                const SingleActivator(LogicalKeyboardKey.enter): _send,
            },
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              maxLines: 8,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              style: text.bodyLarge?.copyWith(color: c.text),
              cursorColor: c.accent,
              decoration: InputDecoration(
                isDense: true,
                // The app theme fills inputs, which is right for a settings
                // field and wrong here: the composer is already a box, so the
                // fill painted a grey band inside a white card. Turned off
                // explicitly rather than by removing it from the theme, since
                // every other field in the app still wants it.
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: Space.sm),
                hintText: widget.hint,
                hintStyle: text.bodyLarge?.copyWith(color: c.textFaint),
              ),
            ),
          ),
          Row(
            children: [
              _RoundButton(
                icon: Icons.add_rounded,
                tooltip: 'Attach',
                // Attachments land with the chat wave. The control is here
                // because its absence changes the composer's proportions, and
                // it says plainly that it is not ready rather than doing
                // nothing when pressed.
                onPressed: null,
              ),
              const Spacer(),
              _SendButton(
                enabled: _hasText && !widget.busy,
                busy: widget.busy,
                onPressed: _send,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _RoundButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: onPressed == null ? '$tooltip — not built yet' : tooltip,
      child: SizedBox(
        width: kMinTouchTarget,
        height: kMinTouchTarget,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          color: c.textMuted,
          disabledColor: c.textFaint,
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  const _SendButton({
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return SizedBox(
      width: kMinTouchTarget,
      height: kMinTouchTarget,
      child: Center(
        child: Material(
          color: enabled ? c.accent : c.surfaceSunken,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              width: 32,
              height: 32,
              child: busy
                  ? Padding(
                      padding: const EdgeInsets.all(9),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.textMuted,
                      ),
                    )
                  : Icon(
                      Icons.arrow_upward_rounded,
                      size: 18,
                      color: enabled ? c.onAccent : c.textFaint,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
