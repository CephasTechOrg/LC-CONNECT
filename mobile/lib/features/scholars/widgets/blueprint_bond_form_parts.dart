part of '../screens/blueprint_bond_screen.dart';

/// One white card per section — title + optional/required/done tag, then the fields.
///
/// [requiredDone] drives the tag on the right: null = optional, false = still required,
/// true = done. It reflects the last *saved* state (the server's `missing_fields`).
class _SectionCard extends StatelessWidget {
  final String title;
  final bool? requiredDone;
  final Widget child;

  const _SectionCard({
    required this.title,
    this.requiredDone,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      // The shared card surface (soft shadow, card radius), same as Home and Activities.
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.all(AppRadii.sheet),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              _RequirementTag(done: requiredDone),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// Splits the required sections from the optional ones — a heading and one muted line, no box.
class _GroupLabel extends StatelessWidget {
  final String title;
  final String detail;
  const _GroupLabel({required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xxl, AppSpacing.xs, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.title.copyWith(color: AppColors.textDark)),
          const SizedBox(height: 2),
          Text(detail, style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _RequirementTag extends StatelessWidget {
  final bool? done;
  const _RequirementTag({this.done});

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.caption.copyWith(fontWeight: FontWeight.w600);
    return switch (done) {
      // Optional sections sit under the "Optional" heading, so a tag on each would repeat it.
      null => const SizedBox.shrink(),
      false => Text('Required', style: style.copyWith(color: _kAmber)),
      true => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 14, color: _kSuccess),
            const SizedBox(width: AppSpacing.xs),
            Text('Done', style: style.copyWith(color: _kSuccess)),
          ],
        ),
    };
  }
}

InputDecoration _fieldDecoration({String? hint}) {
  const border = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppRadii.md)),
    borderSide: BorderSide(color: AppColors.border),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: AppTypography.body.copyWith(color: AppColors.textMuted),
    filled: true,
    fillColor: AppColors.background,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: AppTypography.label.copyWith(color: AppColors.textMid),
        ),
      );
}

class _Field extends StatelessWidget {
  final String? label;
  final TextEditingController controller;
  final int maxLines;
  final String? hint;
  final TextInputType? keyboardType;
  const _Field({
    this.label,
    required this.controller,
    this.maxLines = 1,
    this.hint,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) _FieldLabel(label!),
        TextField(
          controller: controller,
          maxLines: maxLines,
          minLines: maxLines > 1 ? 3 : 1,
          keyboardType: keyboardType,
          style: AppTypography.body.copyWith(color: AppColors.textDark),
          decoration: _fieldDecoration(hint: hint),
        ),
      ],
    );
  }
}

TextStyle get _fileActionStyle =>
    AppTypography.label.copyWith(fontWeight: FontWeight.w700);

/// Résumé slot: status tile, name + state, View / Upload.
class _FileRow extends StatelessWidget {
  final String label;
  final String hint;
  final bool hasFile;
  final bool uploading;
  final VoidCallback onUpload;
  final VoidCallback? onView;
  const _FileRow({
    required this.label,
    required this.hint,
    required this.hasFile,
    required this.uploading,
    required this.onUpload,
    this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: hasFile ? AppColors.green.withValues(alpha: 0.12) : AppColors.background,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Icon(
            hasFile ? Icons.check_rounded : Icons.upload_file_rounded,
            size: 20,
            color: hasFile ? AppColors.green : AppColors.textMuted,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                hasFile ? 'Uploaded' : hint,
                style: AppTypography.caption.copyWith(
                  color: hasFile ? AppColors.green : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        if (onView != null)
          TextButton(
            onPressed: onView,
            style: TextButton.styleFrom(foregroundColor: AppColors.textMid),
            child: Text('View', style: _fileActionStyle),
          ),
        TextButton(
          onPressed: uploading ? null : onUpload,
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          child: uploading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(hasFile ? 'Replace' : 'Upload', style: _fileActionStyle),
        ),
      ],
    );
  }
}

/// Full-width soft button for adding an entry to a list section.
class _AddEntryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _AddEntryButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? AppColors.primarySoft : AppColors.background,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 18, color: enabled ? AppColors.primary : AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.label.copyWith(
                  fontWeight: FontWeight.w700,
                  color: enabled ? AppColors.primary : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagInput extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final Set<String> tags;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  const _TagInput({
    required this.label,
    required this.hint,
    required this.controller,
    required this.tags,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        TextField(
          controller: controller,
          onSubmitted: (_) => onAdd(),
          textInputAction: TextInputAction.done,
          style: AppTypography.body.copyWith(color: AppColors.textDark),
          decoration: _fieldDecoration(hint: hint).copyWith(
            suffixIcon: IconButton(
              tooltip: 'Add ${label.toLowerCase()}',
              onPressed: onAdd,
              icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary),
            ),
          ),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final t in tags)
                InputChip(
                  label: Text(t),
                  labelStyle: AppTypography.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  onDeleted: () => onRemove(t),
                  deleteIconColor: AppColors.primary,
                  backgroundColor: AppColors.primarySoft,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.full)),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Consent switch row inside the Employer visibility card.
class _ConsentRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ConsentRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Visible to employers',
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Switch(
          value: value,
          activeTrackColor: AppColors.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
