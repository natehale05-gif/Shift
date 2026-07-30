import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../../data/stores/conversation_store.dart';
import '../voice/voice_mode_controller.dart';
import '../../data/stores/api_keys_store.dart';

/// Opens hands-free voice mode: you talk, it answers out loud, and it starts
/// listening again. Everything said lands in the conversation as normal
/// messages, so it can be continued by typing afterwards.
Future<void> showVoiceModeOverlay(BuildContext context) {
  final conversations = context.read<ConversationStore>();
  final keys = context.read<ApiKeysStore>();
  return showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (_) =>
        _VoiceModeOverlay(conversations: conversations, keys: keys),
  );
}

class _VoiceModeOverlay extends StatefulWidget {
  final ConversationStore conversations;
  final ApiKeysStore keys;

  const _VoiceModeOverlay({required this.conversations, required this.keys});

  @override
  State<_VoiceModeOverlay> createState() => _VoiceModeOverlayState();
}

class _VoiceModeOverlayState extends State<_VoiceModeOverlay>
    with SingleTickerProviderStateMixin {
  late final VoiceModeController _controller =
      VoiceModeController(
        conversations: widget.conversations,
        keys: widget.keys,
      );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _controller.start();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _pulse.dispose();
    super.dispose();
  }

  String get _status => switch (_controller.phase) {
        VoicePhase.starting => 'Getting the microphone ready…',
        VoicePhase.listening => 'Listening',
        VoicePhase.thinking => 'Thinking',
        VoicePhase.speaking => 'Speaking',
        VoicePhase.idle => 'Voice mode is off',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final problem = _controller.problem;

    return Dialog.fullscreen(
      // Nearly opaque rather than transparent: with the chat legible behind
      // it, the overlay reads as a popup over a page you could still be using
      // — the opposite of what a hands-free mode is.
      backgroundColor: const Color(0xFF0B0A0F),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: 'Close voice mode',
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: () {
                    _controller.stop();
                    Navigator.of(context).pop();
                  },
                ),
              ),
              const Spacer(),
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  size: const Size(180, 180),
                  painter: _OrbPainter(
                    t: _pulse.value,
                    phase: _controller.phase,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                _status,
                style: AppTypography.serifDisplay(
                  fontSize: 26,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // The live transcript is the honest answer to "is this even
              // hearing me" — a silent orb cannot distinguish a quiet room
              // from a broken microphone.
              SizedBox(
                height: 84,
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(
                    problem ?? _controller.heard,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: problem != null
                          ? theme.colorScheme.error
                          : Colors.white70,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (problem == null)
                Text(
                  'Talk normally — it answers when you pause.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: () {
                  _controller.stop();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.stop_rounded),
                label: const Text('End voice mode'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A breathing orb whose motion reports the phase: wide and slow while
/// listening, tight and quick while thinking, broad rings while speaking.
class _OrbPainter extends CustomPainter {
  final double t;
  final VoicePhase phase;
  final Color color;

  _OrbPainter({required this.t, required this.phase, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final base = size.width * 0.24;
    final wave = math.sin(t * 2 * math.pi);

    final (rings, amplitude, speed) = switch (phase) {
      VoicePhase.listening => (3, 0.16, 1.0),
      VoicePhase.thinking => (2, 0.05, 3.0),
      VoicePhase.speaking => (4, 0.22, 1.6),
      _ => (1, 0.02, 0.6),
    };

    for (var i = rings; i >= 1; i--) {
      final offset = math.sin((t * speed + i * 0.18) * 2 * math.pi);
      final radius = base * (1 + i * 0.38) * (1 + amplitude * offset);
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = color.withValues(alpha: 0.10 + 0.06 * (rings - i)),
      );
    }
    canvas.drawCircle(
      center,
      base * (1 + amplitude * 0.5 * wave),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t || old.phase != phase || old.color != color;
}
