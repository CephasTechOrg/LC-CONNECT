part of '../screens/create_activity_screen.dart';

/// Optional event banner picker — a 16:9 tap target showing the newly picked image, the existing
/// banner, or an "add a banner" placeholder.
class _BannerPicker extends StatelessWidget {
  final XFile? picked;
  final String? existingUrl;
  final VoidCallback? onTap;
  const _BannerPicker({required this.picked, required this.existingUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (picked != null) {
      content = Image.file(File(picked!.path), fit: BoxFit.cover);
    } else if (existingUrl != null) {
      content = CachedNetworkImage(
          imageUrl: existingUrl!, fit: BoxFit.cover, errorWidget: (_, _, _) => _placeholder());
    } else {
      content = _placeholder();
    }
    final hasImage = picked != null || existingUrl != null;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AppRadii.all(AppRadii.sheet),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              // The empty state says "add a cover photo" itself; the chip is for changing one.
              if (hasImage)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Text('Change',
                            style: AppTypography.label.copyWith(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The brand's sea-blue wash — the same gradient and soft circle as the Home spotlight — so the
  /// first thing on the form is an invitation in the app's own colours, not a grey box.
  Widget _placeholder() => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEAF2F9), Color(0xFFD7E6F2)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: -60,
              right: -50,
              child: Container(
                width: 180,
                height: 180,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x293F7FB5)),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                  child: const Icon(Icons.add_photo_alternate_outlined, size: 24, color: AppColors.primary),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Add a cover photo',
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Optional · shows at the top of your activity',
                  style: AppTypography.caption.copyWith(color: AppColors.textMid),
                ),
              ],
            ),
          ],
        ),
      );
}

/// A category choice. Selected is the soft tint used by every filter chip in the app, not a
/// solid blue fill — a solid fill made the chosen category louder than the Create button.
class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryText : AppColors.textMid;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
          child: Align(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: selected ? AppColors.primarySoft : AppColors.surface,
                borderRadius: AppRadii.all(AppRadii.full),
                border: Border.all(
                  color: selected ? AppColors.primary.withValues(alpha: 0.35) : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: color),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.bodySmall.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final int? maxLength;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _Field({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.maxLength,
    this.prefixIcon,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      // Without this the keyboard offers a return key that does nothing on a single-line field.
      // `next` advances focus via Flutter's own traversal (EditableText calls `nextFocus()`), so
      // no explicit FocusNode chain is needed. Multiline fields keep the newline key.
      textInputAction: maxLines == 1 ? TextInputAction.next : null,
      textCapitalization: TextCapitalization.sentences,
      style: AppTypography.body.copyWith(color: AppColors.textDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTypography.body.copyWith(color: AppColors.textMuted),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 18, color: AppColors.textMuted)
            : null,
        filled: true,
        fillColor: AppColors.surface,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}

class _DateTimeRow extends StatelessWidget {
  final DateTime? date;
  final TimeOfDay? time;
  final VoidCallback onTapDate;
  final VoidCallback onTapTime;

  const _DateTimeRow({
    required this.date,
    required this.time,
    required this.onTapDate,
    required this.onTapTime,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PickerTile(
            icon: Icons.calendar_today_outlined,
            label: date != null ? DateFormat('EEE, MMM d').format(date!) : 'Pick date',
            hasValue: date != null,
            onTap: onTapDate,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PickerTile(
            icon: Icons.access_time_outlined,
            label: time != null ? time!.format(context) : 'Pick time',
            hasValue: time != null,
            onTap: onTapTime,
          ),
        ),
      ],
    );
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool hasValue;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.label,
    required this.hasValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasValue ? AppColors.primary : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: hasValue ? AppColors.primary : AppColors.textMuted),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  color: hasValue ? AppColors.textDark : AppColors.textMuted,
                  fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
