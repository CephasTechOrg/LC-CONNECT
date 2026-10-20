part of '../screens/chat_screen.dart';

/// "Someone is typing" drawn as an incoming bubble with three dots, sitting where their next
/// message will land rather than as a text strip above the composer.
///
/// In a group it names the typer above the bubble; in a DM the header subtitle already says
/// "typing…", so the bubble alone is enough.
class _TypingBubble extends StatefulWidget {
  final String name;
  final bool showName;
  const _TypingBubble({required this.name, required this.showName});

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: static dots. The label still says what is happening.
    if (MediaQuery.of(context).disableAnimations) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '${widget.name} is typing',
      excludeSemantics: true,
      child: Padding(
        // Lines up with incoming bubbles: list gutter + avatar + gap.
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg + _BubbleTile._avatarSize + AppSpacing.sm,
          0,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showName)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: 2),
                child: Text(
                  '${widget.name} is typing',
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: const BorderRadius.only(
                  topLeft: _BubbleTile._bubbleRadius,
                  topRight: _BubbleTile._bubbleRadius,
                  bottomRight: _BubbleTile._bubbleRadius,
                  bottomLeft: _BubbleTile._tailRadius,
                ),
              ),
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      _dot(i),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Each dot brightens in turn, a third of a cycle apart.
  Widget _dot(int index) {
    double alpha = 0.45;
    if (_pulse.isAnimating) {
      final phase = (_pulse.value - index / 3) % 1.0;
      alpha = phase < 0.33 ? 1.0 : 0.35;
    }
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: AppColors.textMuted.withValues(alpha: alpha),
        shape: BoxShape.circle,
      ),
    );
  }
}
