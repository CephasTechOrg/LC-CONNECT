import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_states.dart';
import '../providers/policies_provider.dart';
import '../widgets/policy_markdown_theme.dart';

/// Full-screen reader for one policy document.
///
/// Pushed, never `go`-ed: it is opened from the signup checkbox and from the acceptance gate, and
/// both need the user returned to exactly where they were — mid-signup with the form still filled
/// in. The register screen already taught us what `go` costs here.
class PolicyDocumentScreen extends ConsumerWidget {
  final String slug;
  const PolicyDocumentScreen({super.key, required this.slug});

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      // Reachable by deep link, where there is nothing beneath this screen.
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(policyDocumentProvider(slug));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: AppColors.textDark),
          onPressed: () => _back(context),
          tooltip: 'Back',
        ),
        title: Text(
          document.value?.title ?? 'Loading…',
          style: AppTypography.titleSmall.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
      ),
      body: SafeArea(
        child: document.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          // The app's one error state, like every other screen that fails to load.
          error: (error, _) => AppErrorState(
            message: apiErrorMessage(
              error,
              fallback: "We couldn't load this document. Check your connection.",
            ),
            onRetry: () => ref.invalidate(policyDocumentProvider(slug)),
          ),
          data: (doc) => Markdown(
            data: doc.body,
            styleSheet: policyMarkdownStyle(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              AppSpacing.xxxl,
            ),
            // Tables in these documents are wider than a phone. Letting them scroll sideways on
            // their own keeps the page from scrolling horizontally as a whole.
            shrinkWrap: false,
            selectable: true,
          ),
        ),
      ),
    );
  }
}
