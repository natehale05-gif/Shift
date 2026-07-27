import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/live/live_voice_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Full-screen realtime voice session (EXPERIMENTAL — Gemini Live API).
Future<void> showLiveVoiceOverlay(BuildContext context, String geminiKey) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black87,
    builder: (_) => _LiveVoiceOverlay(apiKey: geminiKey),
  );
}

class _LiveVoiceOverlay extends StatefulWidget {
  final String apiKey;

  const _LiveVoiceOverlay({required this.apiKey});

  @override
  State<_LiveVoiceOverlay> createState() => _LiveVoiceOverlayState();
}

class _LiveVoiceOverlayState extends State<_LiveVoiceOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  StreamSubscription<LiveVoiceState>? _subscription;
  LiveVoiceState _state =
      const LiveVoiceState(LiveVoicePhase.connecting);
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
      lowerBound: 0.85,
      upperBound: 1.0,
    )..repeat(reverse: true);
    _subscription = LiveVoiceController.start(widget.apiKey).listen(
      (state) => setState(() => _state = state),
      onDone: () {
        if (mounted && _state.phase != LiveVoicePhase.error) {
          Navigator.of(context).maybePop();
        }
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    LiveVoiceController.end();
    _pulse.dispose();
    super.dispose();
  }

  String get _statusLine => switch (_state.phase) {
        LiveVoicePhase.connecting => 'Connecting…',
        LiveVoicePhase.ready => _muted ? 'Muted' : 'Listening…',
        LiveVoicePhase.speaking => 'SHIFT AI is speaking…',
        LiveVoicePhase.error => 'Something broke',
        LiveVoicePhase.closed => 'Session ended',
      };

  @override
  Widget build(BuildContext context) {
    final speaking = _state.phase == LiveVoicePhase.speaking;
    return Dialog.fullscreen(
      backgroundColor: const Color(0xFF0A0A0C),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warningSurfaceDark,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Text(
                  'Experimental — realtime voice may break as Google '
                  'changes the Live API.',
                  style: TextStyle(
                      color: AppColors.warningTextDark, fontSize: 12),
                ),
              ),
            ),
            const Spacer(),
            ScaleTransition(
              scale: speaking
                  ? _pulse
                  : const AlwaysStoppedAnimation(1.0),
              child: Container(
                width: 160,
                height: 160,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.accentDark, AppColors.systemIndigo],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(
                  _state.phase == LiveVoicePhase.error
                      ? Icons.error_outline_rounded
                      : Icons.graphic_eq_rounded,
                  color: Colors.white,
                  size: 56,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              _statusLine,
              style: AppTypography.serifDisplay(
                fontSize: 24,
                color: Colors.white,
              ),
            ),
            if (_state.detail != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Text(
                    _state.detail!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF98989D),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: _muted ? 'Unmute' : 'Mute',
                    iconSize: 26,
                    onPressed: () {
                      setState(() => _muted = !_muted);
                      LiveVoiceController.setMuted(_muted);
                    },
                    icon: Icon(
                      _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  IconButton.filled(
                    tooltip: 'End session',
                    iconSize: 26,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFFF453A),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.call_end_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
