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
        'pending_review' => ('In review', AppColors.primaryText, null),
        'approved' => ('Approved', _kSuccess, null),
        'changes_requested' => (
            'Changes requested',
            _kAmber,
            profile.reviewNote?.isNotEmpty == true
                ? profile.reviewNote
                : 'Honors asked for updates.',
          ),
        'revoked' => (
            'Revoked',
            _kDanger,
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
        borderRadius: AppRadii.all(AppRadii.sheet),
        boxShadow: AppShadows.soft,
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
              // Progress is the accent's job; "done" is said by the pill and the tags.
              color: AppColors.primary,
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

// Status colours, each meaning one thing (DESIGN_PRINCIPLES rule 5) and each AA on white:
// amber = still required, green = done, red = revoked. The lighter shades used before were
// 2.4–3.5:1 — green "Done" was the least readable word on the page.
const _kAmber = AppColors.warning;
const _kSuccess = AppColors.green;
const _kDanger = AppColors.errorText;

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

/// The page's actions, pinned under the form so neither means scrolling past every section.
///
/// Save used to be small text in the app bar's corner — the least visible spot on a long form
/// whose whole job is to be saved. It is the filled button here until the profile can be
/// submitted; then "Submit for Honors review" is the one primary action and Save steps down to an
/// outlined button beside it.
class _ActionBar extends StatelessWidget {
  final bool saving;
  final VoidCallback onSave;
  final bool canSubmit;
  final bool submitting;
  final VoidCallback onSubmit;

  const _ActionBar({
    required this.saving,
    required this.onSave,
    required this.canSubmit,
    required this.submitting,
    required this.onSubmit,
  });

  static const _height = 52.0;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.full));
    Widget spinner(Color color) => SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        );
    final label = AppTypography.body.copyWith(fontWeight: FontWeight.w700);

    final save = canSubmit
        ? OutlinedButton(
            onPressed: saving ? null : onSave,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(_height),
              shape: shape,
              foregroundColor: AppColors.primaryText,
              side: const BorderSide(color: AppColors.border, width: 1.5),
            ),
            child: saving ? spinner(AppColors.primaryText) : Text('Save', style: label),
          )
        : FilledButton(
            onPressed: saving ? null : onSave,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(_height),
              shape: shape,
            ),
            child: saving ? spinner(Colors.white) : Text('Save', style: label.copyWith(color: Colors.white)),
          );

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: [BoxShadow(color: Color(0x0F1B3A5C), blurRadius: 16, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(child: save),
              if (canSubmit) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: submitting ? null : onSubmit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(_height),
                      shape: shape,
                    ),
                    child: submitting
                        ? spinner(Colors.white)
                        : Text(
                            'Submit for Honors review',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: label.copyWith(color: Colors.white),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
