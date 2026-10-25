part of '../screens/compose_campus_post_screen.dart';

/// A field label, matching the Create activity form. Fields inside the required steps that may be
/// left empty carry a muted "optional"; the Optional group needs no tag.
class _Label extends StatelessWidget {
  final String text;
  final bool optional;
  const _Label(this.text, {this.optional = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Text(
            text,
            style: AppTypography.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          if (optional) ...[
            const SizedBox(width: 6),
            Text('optional', style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  final Map<String, String> options;
  final String selected;
  final ValueChanged<String> onSelect;
  const _ChipWrap({required this.options, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    // Run spacing is 0: each chip already carries a 48dp tap target around its 34dp pill.
    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        for (final e in options.entries)
          AppFilterChip(label: e.value, selected: selected == e.key, onTap: () => onSelect(e.key)),
      ],
    );
  }
}

/// The deadline picker: a field-shaped tile, plus a clear button once a date is set.
class _DeadlineTile extends StatelessWidget {
  final String label;
  final bool hasValue;
  final VoidCallback onPick;
  final VoidCallback onClear;
  const _DeadlineTile({
    required this.label,
    required this.hasValue,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final radius = AppRadii.all(AppRadii.lg);
    return Row(
      children: [
        Expanded(
          child: Material(
            color: AppColors.surface,
            borderRadius: radius,
            child: InkWell(
              onTap: onPick,
              borderRadius: radius,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: hasValue ? AppColors.primary : AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_outlined,
                      size: 18,
                      color: hasValue ? AppColors.primaryText : AppColors.textMuted,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      label,
                      style: AppTypography.body.copyWith(
                        color: hasValue ? AppColors.textDark : AppColors.textMuted,
                        fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (hasValue)
          IconButton(
            tooltip: 'Clear deadline',
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
          ),
      ],
    );
  }
}

/// New post: Save draft beside Publish now, the quieter choice outlined — the same pair as the
/// Blueprint Bond bar. Editing has one action.
class _Actions extends StatelessWidget {
  final bool isEditing;
  final bool loading;
  final VoidCallback onSaveDraft;
  final VoidCallback onPublish;
  final VoidCallback onSaveChanges;
  const _Actions({
    required this.isEditing,
    required this.loading,
    required this.onSaveDraft,
    required this.onPublish,
    required this.onSaveChanges,
  });

  static const _size = Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.full));
    final text = AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700);
    if (isEditing) {
      return FilledButton(
        onPressed: loading ? null : onSaveChanges,
        style: FilledButton.styleFrom(minimumSize: _size, shape: shape),
        child: Text(loading ? 'Saving…' : 'Save changes', style: text),
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: loading ? null : onSaveDraft,
            style: OutlinedButton.styleFrom(
              minimumSize: _size,
              shape: shape,
              foregroundColor: AppColors.primaryText,
              side: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            child: Text('Save draft', style: text),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: FilledButton(
            onPressed: loading ? null : onPublish,
            style: FilledButton.styleFrom(minimumSize: _size, shape: shape),
            child: Text(loading ? 'Working…' : 'Publish now', style: text),
          ),
        ),
      ],
    );
  }
}
