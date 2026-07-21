import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/safety_provider.dart';

const _reportReasons = [
  'Harassment or bullying',
  'Spam or fake profile',
  'Inappropriate content',
  'Hate speech or discrimination',
  'Other',
];

const _sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
);

Widget _dragHandle() => Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(2),
      ),
    );

// ── Entry point ───────────────────────────────────────────────────
Future<void> showSafetySheet({
  required BuildContext context,
  required String targetUserId,
  required String targetName,
  required SafetyService safetyService,
  required VoidCallback onBlocked,
}) async {
  final result = await showModalBottomSheet<String?>(
    context: context,
    shape: _sheetShape,
    builder: (_) => _OptionsSheet(targetName: targetName),
  );
  if (!context.mounted) return;
  if (result == 'report') {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: _sheetShape,
      builder: (_) => _ReportSheet(
        targetUserId: targetUserId,
        targetName: targetName,
        safetyService: safetyService,
      ),
    );
  } else if (result == 'block') {
    _confirmBlock(context, targetUserId, targetName, safetyService, onBlocked);
  }
}

// ── Options sheet (Report / Block) ────────────────────────────────
class _OptionsSheet extends StatelessWidget {
  final String targetName;
  const _OptionsSheet({required this.targetName});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dragHandle(),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.flag_outlined,
                  color: AppColors.textMid),
              title: Text(
                'Report $targetName',
                style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w500,
                  color: AppColors.textDark,
                ),
              ),
              subtitle: Text(
                'Flag inappropriate behavior anonymously',
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: AppColors.textMuted),
              ),
              onTap: () => Navigator.of(context).pop('report'),
            ),
            ListTile(
              leading: const Icon(Icons.block_rounded,
                  color: AppColors.error),
              title: Text(
                'Block $targetName',
                style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w500,
                  color: AppColors.error,
                ),
              ),
              subtitle: Text(
                "They won't see your profile or be able to message you",
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: AppColors.textMuted),
              ),
              onTap: () => Navigator.of(context).pop('block'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Block confirmation ─────────────────────────────────────────────
Future<void> _confirmBlock(
  BuildContext context,
  String userId,
  String name,
  SafetyService service,
  VoidCallback onBlocked,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Block $name?',
        style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
      ),
      content: Text(
        "They won't appear in your discovery and won't be able to contact you.",
        style: GoogleFonts.dmSans(color: AppColors.textMid),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Cancel', style: GoogleFonts.dmSans()),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'Block',
            style: GoogleFonts.dmSans(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await service.blockUser(userId);
    onBlocked();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name has been blocked.',
              style: GoogleFonts.dmSans()),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not block. Please try again.',
              style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }
}

// ── Report sheet (reason picker) ──────────────────────────────────
class _ReportSheet extends StatefulWidget {
  final String targetUserId;
  final String targetName;
  final SafetyService safetyService;

  const _ReportSheet({
    required this.targetUserId,
    required this.targetName,
    required this.safetyService,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _selectedReason;
  bool _submitting = false;

  Future<void> _submit() async {
    if (_selectedReason == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.safetyService.reportUser(
        userId: widget.targetUserId,
        reason: _selectedReason!,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Report submitted. Thank you for keeping LC Connect safe.',
            style: GoogleFonts.dmSans(),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not submit report. Please try again.',
              style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _dragHandle()),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Why are you reporting ${widget.targetName}?',
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Your report is anonymous and reviewed by our team.',
                  style: GoogleFonts.dmSans(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _selectedReason,
                onChanged: (v) => setState(() => _selectedReason = v),
                child: Column(
                  children: _reportReasons
                      .map(
                        (reason) => RadioListTile<String>(
                          value: reason,
                          title: Text(
                            reason,
                            style: GoogleFonts.dmSans(
                                fontSize: 14, color: AppColors.textDark),
                          ),
                          activeColor: AppColors.primary,
                          dense: true,
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _selectedReason != null && !_submitting
                        ? _submit
                        : null,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Submit Report',
                            style: GoogleFonts.dmSans(
                                fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
