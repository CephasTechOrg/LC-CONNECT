part of '../screens/blueprint_bond_screen.dart';

/// One scannable line instead of a two-sentence paragraph. The privacy rule is the single most
/// important thing on this screen, so it reads faster as an icon + short statement than as prose
/// a student skims past.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryPale,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Only approved employers can see this — never your social profile.',
              style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.textMid, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Groups the form into scannable sections so it reads as short tasks rather than one long list.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.dmSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 0.7,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final String? hint;
  const _Field({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.dmSans(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textMid)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: GoogleFonts.dmSans(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  final String label;
  final bool hasFile;
  final bool uploading;
  final VoidCallback onUpload;
  final VoidCallback? onView;
  const _FileRow({required this.label, required this.hasFile, required this.uploading, required this.onUpload, this.onView});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(hasFile ? Icons.check_circle_rounded : Icons.upload_file_rounded, size: 18, color: hasFile ? AppColors.green : AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: GoogleFonts.dmSans(fontSize: 13.5, color: AppColors.textDark)),
          ),
          if (onView != null)
            TextButton(onPressed: onView, child: Text('View', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600))),
          TextButton(
            onPressed: uploading ? null : onUpload,
            child: uploading
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(hasFile ? 'Replace' : 'Upload', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}

class _TagInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final Set<String> tags;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  const _TagInput({required this.label, required this.controller, required this.tags, required this.onAdd, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.dmSans(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textMid)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onSubmitted: (_) => onAdd(),
                style: GoogleFonts.dmSans(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Add and press enter',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onAdd,
              icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary),
            ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags
                .map((t) => Chip(
                      label: Text(t, style: GoogleFonts.dmSans(fontSize: 12.5)),
                      onDeleted: () => onRemove(t),
                      backgroundColor: AppColors.primarySoft,
                      side: BorderSide.none,
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}
