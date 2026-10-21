part of '../screens/blueprint_bond_screen.dart';

/// Server field names → what a student calls them. Order follows the server's fill order.
const _kRequiredFieldLabels = {
  'summary': 'Summary',
  'headshot': 'Headshot',
  'resume': 'Résumé',
  'skills': 'Skills',
  'career_interests': 'Career interests',
  'employer_visibility_consent': 'Employer consent',
};

/// Top-of-page summary: review pill, progress, and only the copy that is still useful.
///
/// Privacy is said once ("Approved employers only — never your social profile"). Status
/// paragraphs that restated the same thing are omitted. A reviewer's note is the exception —
/// that is the material the student has to act on.
class _StatusHeader extends StatelessWidget {
  final ScholarProfile profile;
  const _StatusHeader({required this.profile});

  (String pill, Color accent, String? note) get _status => switch (profile.reviewStatus) {
        'pending_review' => ('In review', AppColors.primary, null),
        'approved' => ('Approved', AppColors.green, null),
        'changes_requested' => (
            'Changes requested',
            _kAmber,
            profile.reviewNote?.isNotEmpty == true
                ? profile.reviewNote
                : 'Honors asked for updates.',
          ),
        'revoked' => (
            'Revoked',
            AppColors.error,
            profile.reviewNote?.isNotEmpty == true
                ? profile.reviewNote
                : 'Honors removed partner visibility.',
          ),
        _ => ('Not submitted', AppColors.textMuted, null),
      };

  @override
  Widget build(BuildContext context) {
    final (pill, accent, note) = _status;
    final total = _kRequiredFieldLabels.length;
    final missing = profile.isComplete
        ? const <String>[]
        : profile.missingFields.where(_kRequiredFieldLabels.containsKey).toList();
    final done = (total - missing.length).clamp(0, total);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Employer profile',
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Approved employers only — never your social profile',
            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$done of $total required done',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMid,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _Pill(label: pill, color: accent),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.full),
            child: LinearProgressIndicator(
              value: done / total,
              minHeight: 6,
              backgroundColor: AppColors.primarySoft,
              color: done == total ? AppColors.green : AppColors.primary,
            ),
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Still needed: ${missing.map((f) => _kRequiredFieldLabels[f]).join(', ')}',
              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(note, style: AppTypography.bodySmall.copyWith(color: AppColors.textMid, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

const _kAmber = Color(0xFFD97706);

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Pinned under the form so submitting never means scrolling past every section to find it.
class _SubmitBar extends StatelessWidget {
  final bool submitting;
  final VoidCallback onSubmit;
  const _SubmitBar({required this.submitting, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: SafeArea(
        top: false,
        child: FilledButton(
          onPressed: submitting ? null : onSubmit,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size.fromHeight(kMinTouchTarget),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
          ),
          child: submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  'Submit for Honors review',
                  style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: Colors.white),
                ),
        ),
      ),
    );
  }
}
