import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/scholars_provider.dart';

/// The Presidential Scholar's professional-extension editor — kept fully separate from the
/// social profile (own screen, own provider). Verified-scholar-only; the backend 403s anyone
/// else even if they somehow reach this route.
class BlueprintBondScreen extends ConsumerStatefulWidget {
  const BlueprintBondScreen({super.key});

  @override
  ConsumerState<BlueprintBondScreen> createState() => _BlueprintBondScreenState();
}

class _BlueprintBondScreenState extends ConsumerState<BlueprintBondScreen> {
  final _linkedinCtrl = TextEditingController();
  final _handshakeCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _skillCtrl = TextEditingController();
  final _careerCtrl = TextEditingController();
  final Set<String> _skills = {};
  final Set<String> _careerInterests = {};
  bool _initialized = false;
  bool _saving = false;
  bool _uploadingHeadshot = false;
  bool _uploadingResume = false;

  @override
  void dispose() {
    _linkedinCtrl.dispose();
    _handshakeCtrl.dispose();
    _summaryCtrl.dispose();
    _skillCtrl.dispose();
    _careerCtrl.dispose();
    super.dispose();
  }

  void _initFrom(ScholarProfile p) {
    if (_initialized) return;
    _initialized = true;
    _linkedinCtrl.text = p.linkedinUrl ?? '';
    _handshakeCtrl.text = p.handshakeUrl ?? '';
    _summaryCtrl.text = p.summary ?? '';
    _skills..clear()..addAll(p.skills);
    _careerInterests..clear()..addAll(p.careerInterests);
  }

  void _showError(Object e, {String fallback = 'Something went wrong. Try again.'}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(apiErrorMessage(e, fallback: fallback), style: GoogleFonts.dmSans()),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(scholarProfileNotifierProvider.notifier).updateFields(
            linkedinUrl: _linkedinCtrl.text.trim(),
            handshakeUrl: _handshakeCtrl.text.trim(),
            summary: _summaryCtrl.text.trim(),
            skills: _skills.toList(),
            careerInterests: _careerInterests.toList(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved', style: GoogleFonts.dmSans()),
            backgroundColor: AppColors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadHeadshot() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 85);
    if (image == null || !mounted) return;
    setState(() => _uploadingHeadshot = true);
    try {
      await ref.read(scholarProfileNotifierProvider.notifier).uploadHeadshot(
            path: image.path,
            mimeType: image.mimeType ?? 'image/jpeg',
            filename: image.name,
          );
    } catch (e) {
      _showError(e, fallback: 'Failed to upload headshot. Try again.');
    } finally {
      if (mounted) setState(() => _uploadingHeadshot = false);
    }
  }

  Future<void> _pickAndUploadResume() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'docx']);
    final file = result?.files.single;
    if (file?.path == null || !mounted) return;
    setState(() => _uploadingResume = true);
    try {
      final ext = file!.extension?.toLowerCase();
      final mimeType = ext == 'pdf'
          ? 'application/pdf'
          : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      await ref.read(scholarProfileNotifierProvider.notifier).uploadResume(
            path: file.path!,
            mimeType: mimeType,
            filename: file.name,
          );
    } catch (e) {
      _showError(e, fallback: 'Failed to upload résumé. Try again.');
    } finally {
      if (mounted) setState(() => _uploadingResume = false);
    }
  }

  Future<void> _openResume() async {
    try {
      final url = await ref.read(scholarProfileNotifierProvider.notifier).resumeUrl();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      _showError(e, fallback: "Couldn't open résumé.");
    }
  }

  Future<void> _toggleConsent(bool value) async {
    try {
      await ref.read(scholarProfileNotifierProvider.notifier).setConsent(value);
    } catch (e) {
      _showError(e, fallback: 'Failed to update visibility.');
    }
  }

  void _addTag(TextEditingController ctrl, Set<String> target) {
    final value = ctrl.text.trim();
    if (value.isEmpty) return;
    setState(() {
      target.add(value);
      ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(scholarProfileNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Blueprint Bond', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: AppColors.textDark)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Save', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(apiErrorMessage(e, fallback: 'Could not load your profile.'), style: GoogleFonts.dmSans()),
        ),
        data: (profile) {
          _initFrom(profile);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              const _PrivacyNote(),
              const SizedBox(height: 22),
              const _SectionLabel('Documents'),
              const SizedBox(height: 10),
              _FileRow(
                label: 'Professional headshot',
                hasFile: profile.hasHeadshot,
                uploading: _uploadingHeadshot,
                onUpload: _pickAndUploadHeadshot,
              ),
              const SizedBox(height: 10),
              _FileRow(
                label: 'Résumé (PDF or Word)',
                hasFile: profile.hasResume,
                uploading: _uploadingResume,
                onUpload: _pickAndUploadResume,
                onView: profile.hasResume ? _openResume : null,
              ),
              const SizedBox(height: 24),
              const _SectionLabel('About you'),
              const SizedBox(height: 12),
              _Field(label: 'Professional summary', controller: _summaryCtrl, maxLines: 4),
              const SizedBox(height: 18),
              _TagInput(
                label: 'Skills',
                controller: _skillCtrl,
                tags: _skills,
                onAdd: () => _addTag(_skillCtrl, _skills),
                onRemove: (t) => setState(() => _skills.remove(t)),
              ),
              const SizedBox(height: 18),
              _TagInput(
                label: 'Career interests',
                controller: _careerCtrl,
                tags: _careerInterests,
                onAdd: () => _addTag(_careerCtrl, _careerInterests),
                onRemove: (t) => setState(() => _careerInterests.remove(t)),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Links'),
              const SizedBox(height: 12),
              _Field(label: 'LinkedIn URL', controller: _linkedinCtrl),
              const SizedBox(height: 14),
              _Field(label: 'Handshake URL', controller: _handshakeCtrl),
              const SizedBox(height: 26),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Visible to employers', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: AppColors.textDark)),
                          const SizedBox(height: 2),
                          Text(
                            'Let employer partners discover you.',
                            style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: profile.employerVisibilityConsent,
                      activeTrackColor: AppColors.primary,
                      onChanged: _toggleConsent,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

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

/// Groups the form into scannable sections so it reads as three short tasks rather than one
/// long undifferentiated list of inputs.
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
  const _Field({required this.label, required this.controller, this.maxLines = 1});

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
