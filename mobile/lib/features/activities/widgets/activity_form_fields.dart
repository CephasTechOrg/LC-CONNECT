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
      content = Image.network(existingUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _placeholder());
    } else {
      content = _placeholder();
    }
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
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
                      Text(picked != null || existingUrl != null ? 'Change' : 'Add banner',
                          style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
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

  Widget _placeholder() => Container(
        color: AppColors.primarySoft,
        alignment: Alignment.center,
        child: Icon(Icons.image_outlined, size: 30, color: AppColors.primary.withValues(alpha: 0.6)),
      );
}

// ── Shared form widgets (used by create + edit) ───────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.dmSans(
        fontSize: 13,
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
      style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textMuted),
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
                style: GoogleFonts.dmSans(
                  fontSize: 13,
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
