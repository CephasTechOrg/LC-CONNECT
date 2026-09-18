import 'package:flutter/material.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_theme.dart';

/// Announces a loading placeholder to assistive technology, exactly once.
///
/// The skeletons were previously silent: a screen-reader user heard nothing at all while a screen
/// loaded, which is indistinguishable from an empty screen. Wrapping each *group* rather than each
/// box is deliberate — a list skeleton is twenty boxes, and twenty "Loading" announcements is
/// worse than none. [ExcludeSemantics] silences the decorative shapes inside.
class AppSkeletonSemantics extends StatelessWidget {
  const AppSkeletonSemantics({super.key, required this.child, this.label = 'Loading'});

  final Widget child;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(child: child),
    );
  }
}

/// Placeholder blocks for list/hub loading states (#17).
///
/// Shimmers, because a static grey block reads as content that failed to load rather than content
/// on its way. The animation is the only thing that says "still working".
class AppSkeletonBox extends StatefulWidget {
  const AppSkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = AppRadii.sm,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<AppSkeletonBox> createState() => _AppSkeletonBoxState();
}

class _AppSkeletonBoxState extends State<AppSkeletonBox> with SingleTickerProviderStateMixin {
  static const _fill = Color(0xFFE8EDF2);
  static const _shine = Color(0xFFF3F6F9);

  /// Slow enough to read as breathing rather than flashing — a fast shimmer on a screen full of
  /// boxes is genuinely unpleasant, and a migraine trigger for some people.
  static const _period = Duration(milliseconds: 1400);

  late final AnimationController _controller = AnimationController(vsync: this, duration: _period);

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Respected rather than assumed: someone who has asked the OS to reduce motion gets the
    // static gradient, which is what this widget used to be for everybody.
    final animate = !MediaQuery.disableAnimationsOf(context);
    if (!animate) return _box(const Alignment(-1, 0), const Alignment(1, 0));

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Sweeps the highlight from off-screen left to off-screen right, so the box is never
        // caught mid-flash at rest.
        final t = _controller.value * 4 - 2;
        return _box(Alignment(t - 1, 0), Alignment(t + 1, 0));
      },
    );
  }

  Widget _box(Alignment begin, Alignment end) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        gradient: LinearGradient(begin: begin, end: end, colors: const [_fill, _shine, _fill]),
      ),
    );
  }
}

/// Discovery / connections / directory list placeholder.
class AppListCardSkeleton extends StatelessWidget {
  const AppListCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppSkeletonBox(width: 120, height: 24, borderRadius: 20),
              const Spacer(),
              AppSkeletonBox(width: 24, height: 24, borderRadius: 12),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeletonBox(width: 70, height: 70, borderRadius: 35),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    AppSkeletonBox(width: double.infinity, height: 18),
                    SizedBox(height: 8),
                    AppSkeletonBox(width: 140, height: 14),
                    SizedBox(height: 6),
                    AppSkeletonBox(width: 100, height: 14),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              Expanded(child: AppSkeletonBox(height: 48, borderRadius: 10)),
              SizedBox(width: 10),
              Expanded(child: AppSkeletonBox(height: 48, borderRadius: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class AppListSkeleton extends StatelessWidget {
  const AppListSkeleton({super.key, this.count = 3, this.padding});

  final int count;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonSemantics(
      label: 'Loading list',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: padding ?? const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: List.generate(count, (_) => const AppListCardSkeleton()),
      ),
    );
  }
}

/// Activities tab: one featured block + compact rows.
class AppActivityListSkeleton extends StatelessWidget {
  const AppActivityListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppSkeletonSemantics(
      label: 'Loading activities',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        children: const [
          AppSkeletonBox(width: double.infinity, height: 180, borderRadius: 16),
          SizedBox(height: 16),
          AppSkeletonBox(width: double.infinity, height: 88, borderRadius: 14),
          SizedBox(height: 10),
          AppSkeletonBox(width: double.infinity, height: 88, borderRadius: 14),
        ],
      ),
    );
  }
}

/// Messages thread row placeholder.
class AppThreadRowSkeleton extends StatelessWidget {
  const AppThreadRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: const [
          AppSkeletonBox(width: 52, height: 52, borderRadius: 26),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSkeletonBox(width: double.infinity, height: 16),
                SizedBox(height: 8),
                AppSkeletonBox(width: 180, height: 13),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppThreadListSkeleton extends StatelessWidget {
  const AppThreadListSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonSemantics(
      label: 'Loading conversations',
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: count,
        itemBuilder: (_, _) => const AppThreadRowSkeleton(),
      ),
    );
  }
}

/// Profile tab loading layout.
class AppProfileSkeleton extends StatelessWidget {
  const AppProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppSkeletonSemantics(
      label: 'Loading profile',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: const [
          AppSkeletonBox(width: double.infinity, height: 56, borderRadius: 12),
          SizedBox(height: 20),
          Center(child: AppSkeletonBox(width: 96, height: 96, borderRadius: 48)),
          SizedBox(height: 16),
          Center(child: AppSkeletonBox(width: 160, height: 22, borderRadius: 6)),
          SizedBox(height: 24),
          AppSkeletonBox(width: double.infinity, height: 120, borderRadius: 14),
          SizedBox(height: 12),
          AppSkeletonBox(width: double.infinity, height: 96, borderRadius: 14),
          SizedBox(height: 12),
          AppSkeletonBox(width: double.infinity, height: 72, borderRadius: 14),
        ],
      ),
    );
  }
}

/// Campus hub updates panel placeholder.
/// Full-width content cards — the Campus Hub shape.
///
/// [count] defaults to the two used in a dashboard panel; a full-page list asks for more so the
/// placeholder fills the viewport instead of leaving it half empty.
class AppHubPanelSkeleton extends StatelessWidget {
  const AppHubPanelSkeleton({super.key, this.count = 2});

  final int count;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonSemantics(
      label: 'Loading',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Column(
          children: List.generate(
            count,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppSkeletonBox(width: double.infinity, height: 88, borderRadius: 14),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hub section preview cards (activities / connections).
class AppPreviewCardSkeleton extends StatelessWidget {
  const AppPreviewCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppSkeletonSemantics(
      label: 'Loading',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: AppSkeletonBox(width: double.infinity, height: 76, borderRadius: 16),
      ),
    );
  }
}
