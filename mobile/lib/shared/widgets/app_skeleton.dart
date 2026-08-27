import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Placeholder blocks for list/hub loading states (#17).
class AppSkeletonBox extends StatelessWidget {
  const AppSkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  static const _fill = Color(0xFFE8EDF2);
  static const _shine = Color(0xFFF3F6F9);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [_fill, _shine, _fill],
        ),
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
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: padding ?? const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: List.generate(count, (_) => const AppListCardSkeleton()),
    );
  }
}

/// Activities tab: one featured block + compact rows.
class AppActivityListSkeleton extends StatelessWidget {
  const AppActivityListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
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
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (_, _) => const AppThreadRowSkeleton(),
    );
  }
}

/// Profile tab loading layout.
class AppProfileSkeleton extends StatelessWidget {
  const AppProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
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
    );
  }
}

/// Campus hub updates panel placeholder.
class AppHubPanelSkeleton extends StatelessWidget {
  const AppHubPanelSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: List.generate(
          2,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppSkeletonBox(
              width: double.infinity,
              height: 88,
              borderRadius: 14,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: AppSkeletonBox(
        width: double.infinity,
        height: 76,
        borderRadius: 16,
      ),
    );
  }
}
