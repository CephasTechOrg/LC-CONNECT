import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../campus_positions/providers/campus_positions_provider.dart';
import '../widgets/onboarding_shared_widgets.dart';

const _categories = <String, String>{
  'academic': 'Academic',
  'advising': 'Advising',
  'residential_life': 'Residential Life',
  'campus_services': 'Campus Services',
};

class StaffOnboardingScreen extends ConsumerStatefulWidget {
  const StaffOnboardingScreen({super.key});

  @override
  ConsumerState<StaffOnboardingScreen> createState() => _StaffOnboardingScreenState();
}

class _StaffOnboardingScreenState extends ConsumerState<StaffOnboardingScreen> {
  int _step = 0;
  static const _totalSteps = 3;
  bool _loading = false;

  final _nameCtrl = TextEditingController();
  final _pronounsCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  String? _category;
  final _titleCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _officeCtrl = TextEditingController();

  final _phoneCtrl = TextEditingController();
  final _availabilityCtrl = TextEditingController();
  String? _email;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _email = ref.read(authNotifierProvider).asData?.value?.email;
      if (_nameCtrl.text.isEmpty && _email != null) {
        final prefix = _email!.split('@').first;
        _nameCtrl.text = prefix
            .replaceAll(RegExp(r'[._\-]'), ' ')
            .split(' ')
            .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1).toLowerCase())
            .join(' ')
            .trim();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pronounsCtrl.dispose();
    _bioCtrl.dispose();
    _titleCtrl.dispose();
    _departmentCtrl.dispose();
    _officeCtrl.dispose();
    _phoneCtrl.dispose();
    _availabilityCtrl.dispose();
    super.dispose();
  }

  bool _canProceed() {
    switch (_step) {
      case 0:
        return _nameCtrl.text.trim().isNotEmpty;
      case 1:
        return _category != null &&
            _titleCtrl.text.trim().isNotEmpty &&
            _departmentCtrl.text.trim().isNotEmpty;
      case 2:
        return true;
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
    setState(() => _loading = true);
    try {
      final client = ref.read(apiClientProvider);
      final profileBody = <String, dynamic>{
        'display_name': _nameCtrl.text.trim(),
      };
      if (_pronounsCtrl.text.trim().isNotEmpty) {
        profileBody['pronouns'] = _pronounsCtrl.text.trim();
      }
      if (_bioCtrl.text.trim().isNotEmpty) profileBody['bio'] = _bioCtrl.text.trim();
      await client.dio.patch('/profiles/me', data: profileBody);

      await ref.read(campusPositionsServiceProvider).submitPosition(
            category: _category!,
            officialTitle: _titleCtrl.text.trim(),
            department: _departmentCtrl.text.trim(),
            officeLocation: _officeCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            availability: _availabilityCtrl.text.trim(),
            bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
          );

      await ref.read(authNotifierProvider.notifier).refreshProfile();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Something went wrong. Please try again.', style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Basic Profile', 'Campus Position', 'Contact & Submit'];
    final subtitles = [
      'How you appear on LC Connect',
      'Your official campus role',
      'How students can reach you',
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
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
                        'Staff Setup',
                        style: GoogleFonts.dmSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  OnboardingStepIndicator(currentStep: _step, totalSteps: _totalSteps),
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
                    style: GoogleFonts.dmSans(fontSize: 13.5, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 18),
                  const Divider(color: AppColors.border, height: 1),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
                child: _buildStep(),
              ),
            ),
            OnboardingBottomBar(
              step: _step,
              totalSteps: _totalSteps,
              isLoading: _loading,
              canProceed: _canProceed(),
              onBack: _onBack,
              onNext: _onNext,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _stepBasic();
      case 1:
        return _stepPosition();
      default:
        return _stepContact();
    }
  }

  Widget _stepBasic() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const OnboardingLabel('Display Name'),
        TextFormField(
          controller: _nameCtrl,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Your name on LC Connect'),
        ),
        const SizedBox(height: 16),
        const OnboardingLabel('Pronouns', optional: true),
        TextFormField(
          controller: _pronounsCtrl,
          decoration: const InputDecoration(hintText: 'e.g., she/her, he/him'),
        ),
        const SizedBox(height: 16),
        const OnboardingLabel('Short Bio', optional: true),
        TextFormField(
          controller: _bioCtrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'A brief introduction'),
        ),
      ],
    );
  }

  Widget _stepPosition() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const OnboardingLabel('Campus Category'),
        DropdownButtonFormField<String>(
          initialValue: _category,
          items: _categories.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) => setState(() => _category = v),
          decoration: const InputDecoration(hintText: 'Select a category'),
        ),
        const SizedBox(height: 16),
        const OnboardingLabel('Official Title'),
        TextFormField(
          controller: _titleCtrl,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'e.g., Associate Professor'),
        ),
        const SizedBox(height: 16),
        const OnboardingLabel('Department or Office'),
        TextFormField(
          controller: _departmentCtrl,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'e.g., Biology Department'),
        ),
        const SizedBox(height: 16),
        const OnboardingLabel('Office Location', optional: true),
        TextFormField(
          controller: _officeCtrl,
          decoration: const InputDecoration(hintText: 'Building and room'),
        ),
      ],
    );
  }

  Widget _stepContact() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const OnboardingLabel('Official Email'),
        TextFormField(
          initialValue: _email,
          readOnly: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.lock_outline, size: 18, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 16),
        const OnboardingLabel('Phone', optional: true),
        TextFormField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: 'Office or campus phone'),
        ),
        const SizedBox(height: 16),
        const OnboardingLabel('Office Hours', optional: true),
        TextFormField(
          controller: _availabilityCtrl,
          maxLines: 2,
          decoration: const InputDecoration(hintText: 'When students can reach you'),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Your position will be reviewed by an administrator before appearing in the campus directory.',
            style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.textMid, height: 1.4),
          ),
        ),
      ],
    );
  }
}
