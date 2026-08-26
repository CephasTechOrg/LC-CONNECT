part of '../screens/profile_screen.dart';

Future<void> _showExportAccountFlow(BuildContext context, WidgetRef ref) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final data = await ref.read(accountServiceProvider).exportAccount();
    if (!context.mounted) return;
    Navigator.of(context).pop(); // loading

    final encoded = const JsonEncoder.withIndent('  ').convert(data);
    await Clipboard.setData(ClipboardData(text: encoded));
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Your data export is ready',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'A JSON copy of your LC Connect data has been copied to the clipboard. '
          'Paste it into Notes, email, or a file to keep it.',
          style: GoogleFonts.dmSans(color: AppColors.textMid, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Done', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop(); // loading
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          apiErrorMessage(e, fallback: 'Could not export your data. Please try again.'),
          style: GoogleFonts.dmSans(),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
