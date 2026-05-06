import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/onboarding_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
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

  // Step 2 — Connect
  final Set<String> _lookingFor = {};
  final Set<String> _langSpoken = {};
  final Set<String> _langLearning = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authNotifierProvider).asData?.value;
      if (user != null && _nameCtrl.text.isEmpty) {
        final prefix = user.email.split('@').first;
        _nameCtrl.text = prefix
            .replaceAll(RegExp(r'[._\-]'), ' ')
            .split(' ')
            .map((w) => w.isEmpty
                ? ''
                : w[0].toUpperCase() + w.substring(1).toLowerCase())
            .join(' ')
            .trim();
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
            'Something went wrong. Please try again.',
            style: GoogleFonts.dmSans(),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      // Refresh profileCompleted in auth state → router redirects to /home
      await ref.read(authNotifierProvider.notifier).refreshProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(onboardingNotifierProvider).isLoading;
    final lookups = ref.watch(lookupDataProvider);

    return Scaffold(
      backgroundColor: Colors.white,
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
                      Text('Failed to load options',
                          style: GoogleFonts.dmSans(
                              color: AppColors.textMuted)),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => ref.invalidate(lookupDataProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (data) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
                  child: _buildStepContent(data),
                ),
              ),
            ),
            _buildBottomBar(isLoading),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final titles = ['About You', 'Your Vibe', 'Connect'];
    final subtitles = [
      'Help others find you on campus',
      'Share what makes you unique',
      'Who are you looking to meet?',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  'LC',
                  style: GoogleFonts.dmSans(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Set Up Your Profile',
                style: GoogleFonts.dmSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _StepIndicator(currentStep: _step, totalSteps: _totalSteps),
          const SizedBox(height: 18),
          Text(
            titles[_step],
            style: GoogleFonts.dmSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitles[_step],
            style: GoogleFonts.dmSans(
                fontSize: 13.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 18),
          const Divider(color: AppColors.border, height: 1),
        ],
      ),
    );
  }

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
        _Label('Full Name'),
        TextFormField(
          controller: _nameCtrl,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.words,
          style:
              GoogleFonts.dmSans(fontSize: 14, color: AppColors.textDark),
          decoration: const InputDecoration(
            hintText: 'Your display name',
            prefixIcon: Icon(Icons.person_outline_rounded,
                size: 18, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 16),
        _Label('Pronouns', optional: true),
        TextFormField(
          controller: _pronounsCtrl,
          style:
              GoogleFonts.dmSans(fontSize: 14, color: AppColors.textDark),
          decoration: const InputDecoration(
            hintText: 'e.g., she/her, he/him, they/them',
            prefixIcon: Icon(Icons.tag_rounded,
                size: 18, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 16),
        _Label('Major'),
        TextFormField(
          controller: _majorCtrl,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.words,
          style:
              GoogleFonts.dmSans(fontSize: 14, color: AppColors.textDark),
          decoration: const InputDecoration(
            hintText: 'e.g., Business Administration',
            prefixIcon: Icon(Icons.school_outlined,
                size: 18, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 16),
        _Label('Class Year'),
        DropdownButtonFormField<int>(
          initialValue: _classYear,
          onChanged: (v) => setState(() => _classYear = v),
          style:
              GoogleFonts.dmSans(fontSize: 14, color: AppColors.textDark),
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
        _Label('Short Bio', optional: true),
        TextFormField(
          controller: _bioCtrl,
          maxLines: 4,
          maxLength: 500,
          style:
              GoogleFonts.dmSans(fontSize: 14, color: AppColors.textDark),
          decoration: const InputDecoration(
            hintText: 'Tell people about yourself...',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        _Label('Where are you from?', optional: true),
        TextFormField(
          controller: _locationCtrl,
          style:
              GoogleFonts.dmSans(fontSize: 14, color: AppColors.textDark),
          decoration: const InputDecoration(
            hintText: 'e.g., Atlanta, GA',
            prefixIcon: Icon(Icons.location_on_outlined,
                size: 18, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 22),
        _Label('Interests', optional: true),
        const SizedBox(height: 10),
        _ChipGrid(
          options: data.interests,
          selected: _interests,
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
        Row(
          children: [
            Text(
              "I'm looking for",
              style: GoogleFonts.dmSans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '— pick at least one',
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ChipGrid(
          options: data.lookingFor.map((l) => l['name']!).toList(),
          optionKeys: data.lookingFor.map((l) => l['code']!).toList(),
          selected: _lookingFor,
          onToggle: (v) => setState(() {
            _lookingFor.contains(v)
                ? _lookingFor.remove(v)
                : _lookingFor.add(v);
          }),
          highlight: true,
        ),
        const SizedBox(height: 24),
        _Label('Languages I speak', optional: true),
        const SizedBox(height: 10),
        _ChipGrid(
          options: data.languages,
          selected: _langSpoken,
          onToggle: (v) => setState(() {
            _langSpoken.contains(v)
                ? _langSpoken.remove(v)
                : _langSpoken.add(v);
          }),
        ),
        const SizedBox(height: 24),
        _Label("Languages I'm learning", optional: true),
        const SizedBox(height: 10),
        _ChipGrid(
          options: data.languages,
          selected: _langLearning,
          onToggle: (v) => setState(() {
            _langLearning.contains(v)
                ? _langLearning.remove(v)
                : _langLearning.add(v);
          }),
        ),
      ],
    );
  }

  // ── Bottom navigation bar ──────────────────────────────────────────
  Widget _buildBottomBar(bool isLoading) {
    final canProceed = _canProceed();
    final isLast = _step == _totalSteps - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (_step > 0) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: isLoading ? null : _onBack,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: (canProceed && !isLoading) ? _onNext : null,
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(isLast ? 'Finish Setup' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step progress indicator ────────────────────────────────────────
class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const _StepIndicator(
      {required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps * 2 - 1, (i) {
        if (i.isOdd) {
          final isComplete = (i ~/ 2) < currentStep;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 2,
              color: isComplete ? AppColors.primary : AppColors.border,
            ),
          );
        }
        final idx = i ~/ 2;
        final isComplete = idx < currentStep;
        final isActive = idx == currentStep;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isComplete || isActive ? AppColors.primary : Colors.white,
            border: Border.all(
              color: isComplete || isActive
                  ? AppColors.primary
                  : AppColors.border,
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: isComplete
              ? const Icon(Icons.check_rounded,
                  size: 14, color: Colors.white)
              : Text(
                  '${idx + 1}',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.white : AppColors.textMuted,
                  ),
                ),
        );
      }),
    );
  }
}

// ── Field label ────────────────────────────────────────────────────
class _Label extends StatelessWidget {
  final String text;
  final bool optional;
  const _Label(this.text, {this.optional = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            text,
            style: GoogleFonts.dmSans(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textMid,
            ),
          ),
          if (optional) ...[
            const SizedBox(width: 6),
            Text(
              'optional',
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Animated chip grid ─────────────────────────────────────────────
class _ChipGrid extends StatelessWidget {
  final List<String> options;
  final List<String>? optionKeys;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final bool highlight;

  const _ChipGrid({
    required this.options,
    this.optionKeys,
    required this.selected,
    required this.onToggle,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(options.length, (i) {
        final key = optionKeys?[i] ?? options[i];
        final label = options[i];
        final isOn = selected.contains(key);
        return GestureDetector(
          onTap: () => onToggle(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isOn
                  ? (highlight
                      ? AppColors.primary
                      : AppColors.primarySoft)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isOn ? AppColors.primary : AppColors.border,
                width: 1.5,
              ),
            ),
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight:
                    isOn ? FontWeight.w600 : FontWeight.w400,
                color: isOn
                    ? (highlight ? Colors.white : AppColors.primary)
                    : AppColors.textMid,
              ),
            ),
          ),
        );
      }),
    );
  }
}
