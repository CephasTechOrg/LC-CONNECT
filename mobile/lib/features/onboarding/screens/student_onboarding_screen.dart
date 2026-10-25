import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/suggested_name.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_header.dart';
import '../widgets/onboarding_shared_widgets.dart';

class StudentOnboardingScreen extends ConsumerStatefulWidget {
  const StudentOnboardingScreen({super.key});

  @override
  ConsumerState<StudentOnboardingScreen> createState() => _StudentOnboardingScreenState();
}

class _StudentOnboardingScreenState extends ConsumerState<StudentOnboardingScreen> {
  int _step = 0;
  static const _totalSteps = 3;

  // Step 0 — Basics
  final _nameCtrl = TextEditingController();
  final _pronounsCtrl = TextEditingController();
  final _majorCtrl = TextEditingController();
  int? _classYear;

  // Step 1 — About
  final _bioCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final Set<String> _interests = {};
  final Set<String> _customInterests = {};

  // Step 2 — Connect
  final Set<String> _lookingFor = {};
  final Set<String> _langSpoken = {};
  final Set<String> _langLearning = {};
  final Set<String> _customLanguages = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authNotifierProvider).asData?.value;
      if (user != null && _nameCtrl.text.isEmpty) {
        _nameCtrl.text = suggestedDisplayName(user);
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pronounsCtrl.dispose();
    _majorCtrl.dispose();
    _bioCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  bool _canProceed() {
    switch (_step) {
      case 0:
        return _nameCtrl.text.trim().isNotEmpty &&
            _majorCtrl.text.trim().isNotEmpty &&
            _classYear != null;
      case 1:
        return true;
      case 2:
        return _lookingFor.isNotEmpty;
      default:
        return false;
    }
  }

  void _onNext() {
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _onBack() {
    if (_step > 0) setState(() => _step--);
  }

  Future<void> _submit() async {
    await ref.read(onboardingNotifierProvider.notifier).submit(
          displayName: _nameCtrl.text.trim(),
          pronouns: _pronounsCtrl.text.trim().isEmpty
              ? null
              : _pronounsCtrl.text.trim(),
          major: _majorCtrl.text.trim(),
          classYear: _classYear!,
          countryState: _locationCtrl.text.trim().isEmpty
              ? null
              : _locationCtrl.text.trim(),
          bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
          interests: _interests.toList(),
          languagesSpoken: _langSpoken.toList(),
          languagesLearning: _langLearning.toList(),
          lookingForCodes: _lookingFor.toList(),
        );
    if (!mounted) return;
    final error = ref.read(onboardingNotifierProvider).error;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            apiErrorMessage(error, fallback: 'Something went wrong. Please try again.'),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      await _finishSetup();
    }
  }

  /// Refreshes `profileCompleted` so the router can move to /home.
  ///
  /// The profile is already stored by the time this runs, so a failure here is not a save failure
  /// and must not be reported as one. It used to be swallowed entirely, which left the student on
  /// this screen with no error and a Finish button that silently re-saved the same data.
  Future<void> _finishSetup() async {
    try {
      await ref.read(authNotifierProvider.notifier).refreshProfile();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your profile was saved, but we could not finish setting up. '
            'Check your connection and retry.',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _finishSetup,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(onboardingNotifierProvider).isLoading;
    final lookups = ref.watch(lookupDataProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: lookups.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          size: 48, color: AppColors.textMuted),
                      const SizedBox(height: 12),
                      Text("Couldn't load the options",
                          style: AppTypography.body.copyWith(color: AppColors.textMuted)),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => ref.invalidate(lookupDataProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (data) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxxl),
                  child: _buildStepContent(data),
                ),
              ),
            ),
            OnboardingBottomBar(
              step: _step,
              totalSteps: _totalSteps,
              isLoading: isLoading,
              canProceed: _canProceed(),
              onBack: _onBack,
              onNext: _onNext,
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────
  static const _stepTitles = ['About you', 'Your vibe', 'Connect'];
  static const _stepSubtitles = [
    'Help others find you on campus',
    'Share what makes you unique',
    'Who are you looking to meet?',
  ];

  Widget _buildHeader() => OnboardingHeader(
        // The first screen after signup, so it greets them by the name they just gave.
        flowTitle: onboardingWelcome(
          ref.watch(authNotifierProvider).asData?.value,
          fallback: 'Set up your profile',
        ),
        step: _step,
        totalSteps: _totalSteps,
        stepTitle: _stepTitles[_step],
        stepSubtitle: _stepSubtitles[_step],
      );

  // ── Step content router ────────────────────────────────────────────
  Widget _buildStepContent(LookupData data) {
    switch (_step) {
      case 0:
        return _buildStep0();
      case 1:
        return _buildStep1(data);
      case 2:
        return _buildStep2(data);
      default:
        return const SizedBox();
    }
  }

  // ── Step 0: Basics ────────────────────────────────────────────────
  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        OnboardingLabel('Full name'),
        TextFormField(
          controller: _nameCtrl,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Your display name',
            prefixIcon: Icon(Icons.person_outline_rounded,
                size: 18, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 16),
        OnboardingLabel('Pronouns', optional: true),
        TextFormField(
          controller: _pronounsCtrl,
          decoration: const InputDecoration(
            hintText: 'e.g., she/her, he/him, they/them',
            prefixIcon: Icon(Icons.tag_rounded,
                size: 18, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 16),
        OnboardingLabel('Major'),
        TextFormField(
          controller: _majorCtrl,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g., Business Administration',
            prefixIcon: Icon(Icons.school_outlined,
                size: 18, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 16),
        OnboardingLabel('Class year'),
        DropdownButtonFormField<int>(
          initialValue: _classYear,
          onChanged: (v) => setState(() => _classYear = v),
          // A dropdown styles its hint from `style`; without it the hint rendered bold, unlike the
          // text fields above.
          style: AppTypography.body.copyWith(color: AppColors.textDark),
          decoration: const InputDecoration(
            hintText: 'Select graduation year',
            prefixIcon: Icon(Icons.calendar_today_outlined,
                size: 18, color: AppColors.textMuted),
          ),
          items: List.generate(10, (i) => 2022 + i)
              .map((y) =>
                  DropdownMenuItem(value: y, child: Text('$y')))
              .toList(),
        ),
      ],
    );
  }

  // ── Step 1: About + Interests ──────────────────────────────────────
  Widget _buildStep1(LookupData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        OnboardingLabel('Short bio', optional: true),
        TextFormField(
          controller: _bioCtrl,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'Tell people about yourself...',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        OnboardingLabel('Where are you from?', optional: true),
        TextFormField(
          controller: _locationCtrl,
          decoration: const InputDecoration(
            hintText: 'e.g., Atlanta, GA',
            prefixIcon: Icon(Icons.location_on_outlined,
                size: 18, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 22),
        OnboardingLabel('Interests', optional: true),
        OnboardingChipGrid(
          options: [...data.interests, ..._customInterests],
          selected: _interests,
          maxSelections: kMaxSelections,
          onAddCustom: (value) => setState(() {
            _customInterests.add(value);
            _interests.add(value);
          }),
          onToggle: (v) => setState(() {
            _interests.contains(v)
                ? _interests.remove(v)
                : _interests.add(v);
          }),
        ),
      ],
    );
  }

  // ── Step 2: Looking for + Languages ───────────────────────────────
  Widget _buildStep2(LookupData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        // The one required group on this step says so in the label's own muted words — it used
        // to be blue, colour that meant nothing the rest of the form did not also mean.
        const OnboardingLabel("I'm open to"),
        Text(
          'Pick at least one',
          style: AppTypography.label.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpacing.xs),
        OnboardingChipGrid(
          options: data.lookingFor.map((l) => l['name']!).toList(),
          optionKeys: data.lookingFor.map((l) => l['code']!).toList(),
          selected: _lookingFor,
          onToggle: (v) => setState(() {
            _lookingFor.contains(v)
                ? _lookingFor.remove(v)
                : _lookingFor.add(v);
          }),
        ),
        const SizedBox(height: 24),
        OnboardingLabel('Languages I speak', optional: true),
        OnboardingChipGrid(
          options: [...data.languages, ..._customLanguages],
          selected: _langSpoken,
          maxSelections: kMaxSelections,
          onAddCustom: (value) => setState(() {
            _customLanguages.add(value);
            _langSpoken.add(value);
          }),
          onToggle: (v) => setState(() {
            _langSpoken.contains(v)
                ? _langSpoken.remove(v)
                : _langSpoken.add(v);
          }),
        ),
        const SizedBox(height: 24),
        OnboardingLabel("Languages I'm learning", optional: true),
        OnboardingChipGrid(
          options: [...data.languages, ..._customLanguages],
          selected: _langLearning,
          maxSelections: kMaxSelections,
          onAddCustom: (value) => setState(() {
            _customLanguages.add(value);
            _langLearning.add(value);
          }),
          onToggle: (v) => setState(() {
            _langLearning.contains(v)
                ? _langLearning.remove(v)
                : _langLearning.add(v);
          }),
        ),
      ],
    );
  }
}
