import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/scholars_provider.dart';

part '../widgets/blueprint_bond_form_parts.dart';
part '../widgets/blueprint_bond_experience.dart';

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
  final List<ScholarInternship> _internships = [];
  final List<ScholarProject> _projects = [];
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
    _skills
      ..clear()
      ..addAll(p.skills);
    _careerInterests
      ..clear()
      ..addAll(p.careerInterests);
    _internships
      ..clear()
      ..addAll(p.internships);
    _projects
      ..clear()
      ..addAll(p.projects);
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
            internships: List.of(_internships),
            projects: List.of(_projects),
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

  Future<void> _addInternship() async {
    final entry = await showInternshipEditor(context);
    if (entry == null || !mounted) return;
    setState(() => _internships.add(entry));
  }

  Future<void> _editInternship(int index, ScholarInternship current) async {
    final entry = await showInternshipEditor(context, initial: current);
    if (entry == null || !mounted) return;
    setState(() => _internships[index] = entry);
  }

  Future<void> _addProject() async {
    final entry = await showProjectEditor(context);
    if (entry == null || !mounted) return;
    setState(() => _projects.add(entry));
  }

  Future<void> _editProject(int index, ScholarProject current) async {
    final entry = await showProjectEditor(context, initial: current);
    if (entry == null || !mounted) return;
    setState(() => _projects[index] = entry);
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
              const SizedBox(height: 24),
              _InternshipSection(
                items: _internships,
                onAdd: _addInternship,
                onRemove: (i) => setState(() => _internships.removeAt(i)),
                onEdit: _editInternship,
              ),
              const SizedBox(height: 24),
              _ProjectSection(
                items: _projects,
                onAdd: _addProject,
                onRemove: (i) => setState(() => _projects.removeAt(i)),
                onEdit: _editProject,
              ),
              const SizedBox(height: 24),
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
