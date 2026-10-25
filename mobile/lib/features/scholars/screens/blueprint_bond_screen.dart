import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/a11y.dart';
import '../providers/scholars_provider.dart';

part '../widgets/blueprint_bond_form_parts.dart';
part '../widgets/blueprint_bond_headshot.dart';
part '../widgets/blueprint_bond_experience.dart';
part '../widgets/blueprint_bond_status.dart';

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
  bool _submitting = false;
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
        final status = ref.read(scholarProfileNotifierProvider).asData?.value.reviewStatus;
        final msg = status == 'pending_review'
            ? 'Saved — back in Honors review until approved again'
            : 'Saved';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, style: GoogleFonts.dmSans()),
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

  Future<void> _submitForReview() async {
    setState(() => _submitting = true);
    try {
      // Persist local edits first so Honors reviews what the student currently sees.
      await ref.read(scholarProfileNotifierProvider.notifier).updateFields(
            linkedinUrl: _linkedinCtrl.text.trim(),
            handshakeUrl: _handshakeCtrl.text.trim(),
            summary: _summaryCtrl.text.trim(),
            skills: _skills.toList(),
            careerInterests: _careerInterests.toList(),
            internships: List.of(_internships),
            projects: List.of(_projects),
          );
      await ref.read(scholarProfileNotifierProvider.notifier).submitForReview();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Submitted for Honors review', style: GoogleFonts.dmSans()),
            backgroundColor: AppColors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      _showError(e, fallback: 'Could not submit for review.');
    } finally {
      if (mounted) setState(() => _submitting = false);
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
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Blueprint Bond',
          style: AppTypography.title.copyWith(fontWeight: FontWeight.w800, color: AppColors.textDark),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(apiErrorMessage(e, fallback: 'Could not load your profile.'), style: GoogleFonts.dmSans()),
        ),
        data: (profile) {
          _initFrom(profile);
          return Column(
            children: [
              Expanded(child: _buildForm(profile)),
              _ActionBar(
                saving: _saving,
                onSave: _save,
                canSubmit: profile.canSubmitForReview,
                submitting: _submitting,
                onSubmit: _submitForReview,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildForm(ScholarProfile profile) {
    bool doneUnless(List<String> fields) =>
        profile.isComplete || !fields.any(profile.missingFields.contains);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxl),
      children: [
        _StatusHeader(profile: profile),
        // Everything employers need, in one run: the required sections first, so the page reads
        // top to bottom as a checklist. Employer visibility — required, and the one that
        // actually shares the profile — used to sit last, after three optional sections.
        _SectionCard(
          title: 'Documents',
          requiredDone: doneUnless(const ['headshot', 'resume']),
          child: Column(
            children: [
              _HeadshotRow(
                hasFile: profile.hasHeadshot,
                uploading: _uploadingHeadshot,
                onUpload: _pickAndUploadHeadshot,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Divider(height: 1, color: AppColors.border),
              ),
              _FileRow(
                label: 'Résumé',
                hint: 'PDF or Word',
                hasFile: profile.hasResume,
                uploading: _uploadingResume,
                onUpload: _pickAndUploadResume,
                onView: profile.hasResume ? _openResume : null,
              ),
            ],
          ),
        ),
        _SectionCard(
          title: 'About you',
          requiredDone: doneUnless(const ['summary']),
          child: _Field(
            controller: _summaryCtrl,
            maxLines: 5,
            hint: 'What you study, what you are good at, and what you are looking for.',
          ),
        ),
        _SectionCard(
          title: 'Skills & interests',
          requiredDone: doneUnless(const ['skills', 'career_interests']),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TagInput(
                label: 'Skills',
                hint: 'e.g. Python, public speaking',
                controller: _skillCtrl,
                tags: _skills,
                onAdd: () => _addTag(_skillCtrl, _skills),
                onRemove: (t) => setState(() => _skills.remove(t)),
              ),
              const SizedBox(height: AppSpacing.lg),
              _TagInput(
                label: 'Career interests',
                hint: 'e.g. Software engineering',
                controller: _careerCtrl,
                tags: _careerInterests,
                onAdd: () => _addTag(_careerCtrl, _careerInterests),
                onRemove: (t) => setState(() => _careerInterests.remove(t)),
              ),
            ],
          ),
        ),
        _SectionCard(
          title: 'Employer visibility',
          requiredDone: doneUnless(const ['employer_visibility_consent']),
          child: _ConsentRow(
            value: profile.employerVisibilityConsent,
            onChanged: _toggleConsent,
          ),
        ),
        const _GroupLabel(
          title: 'Optional',
          detail: 'Not needed to submit, but they make your profile stronger.',
        ),
        _SectionCard(
          title: 'Experience',
          child: _InternshipSection(
            items: _internships,
            onAdd: _addInternship,
            onRemove: (i) => setState(() => _internships.removeAt(i)),
            onEdit: _editInternship,
          ),
        ),
        _SectionCard(
          title: 'Projects',
          child: _ProjectSection(
            items: _projects,
            onAdd: _addProject,
            onRemove: (i) => setState(() => _projects.removeAt(i)),
            onEdit: _editProject,
          ),
        ),
        _SectionCard(
          title: 'Links',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Field(
                label: 'LinkedIn URL',
                controller: _linkedinCtrl,
                hint: 'linkedin.com/in/…',
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: AppSpacing.md),
              _Field(
                label: 'Handshake URL',
                controller: _handshakeCtrl,
                hint: 'Optional',
                keyboardType: TextInputType.url,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
