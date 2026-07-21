import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/activities_provider.dart';

const _categories = [
  ('study', 'Study', Icons.menu_book_outlined),
  ('sports', 'Sports', Icons.sports_outlined),
  ('social', 'Social', Icons.people_outline),
  ('culture', 'Culture', Icons.palette_outlined),
];

class CreateActivityScreen extends ConsumerStatefulWidget {
  const CreateActivityScreen({super.key});

  @override
  ConsumerState<CreateActivityScreen> createState() =>
      _CreateActivityScreenState();
}

class _CreateActivityScreenState extends ConsumerState<CreateActivityScreen> {
  final _titleCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  String? _category;
  DateTime? _startDate;
  TimeOfDay? _startTime;
  DateTime? _endDate;
  TimeOfDay? _endTime;
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    _descCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _titleCtrl.text.trim().isNotEmpty &&
      _category != null &&
      _locationCtrl.text.trim().isNotEmpty &&
      _startDate != null &&
      _startTime != null &&
      !_submitting;

  DateTime _combine(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? (_startDate ?? now) : (_endDate ?? _startDate ?? now);
    final first = isStart ? now : (_startDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial =
        isStart ? (_startTime ?? TimeOfDay.now()) : (_endTime ?? TimeOfDay.now());
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      final startDt = _combine(_startDate!, _startTime!);
      DateTime? endDt;
      if (_endDate != null && _endTime != null) {
        endDt = _combine(_endDate!, _endTime!);
      }
      final maxP = _maxCtrl.text.trim().isNotEmpty
          ? int.tryParse(_maxCtrl.text.trim())
          : null;

      await ref.read(activitiesNotifierProvider.notifier).create(
            title: _titleCtrl.text.trim(),
            category: _category!,
            location: _locationCtrl.text.trim(),
            startTime: startDt,
            endTime: endDt,
            description: _descCtrl.text.trim().isNotEmpty
                ? _descCtrl.text.trim()
                : null,
            maxParticipants: maxP,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Activity created!', style: GoogleFonts.dmSans()),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create activity. Please try again.',
              style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Create Activity'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, 12 + MediaQuery.of(context).viewPadding.bottom),
        child: ListenableBuilder(
          listenable: Listenable.merge([_titleCtrl, _locationCtrl]),
          builder: (_, _) => FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    'Create Activity',
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title ─────────────────────────────────────────
            _Label('Title'),
            const SizedBox(height: 8),
            _Field(
              controller: _titleCtrl,
              hint: "What's happening?",
              maxLength: 120,
            ),
            const SizedBox(height: 20),

            // ── Category ──────────────────────────────────────
            _Label('Category'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((c) {
                final (code, label, icon) = c;
                final selected = _category == code;
                return GestureDetector(
                  onTap: () => setState(() => _category = code),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : AppColors.border,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon,
                            size: 15,
                            color: selected
                                ? Colors.white
                                : AppColors.textMuted),
                        const SizedBox(width: 7),
                        Text(
                          label,
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? Colors.white
                                : AppColors.textMid,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ── Location ──────────────────────────────────────
            _Label('Location'),
            const SizedBox(height: 8),
            _Field(
              controller: _locationCtrl,
              hint: 'Where is it?',
              prefixIcon: Icons.location_on_outlined,
              maxLength: 160,
            ),
            const SizedBox(height: 20),

            // ── Start date & time ─────────────────────────────
            _Label('Start'),
            const SizedBox(height: 8),
            _DateTimeRow(
              date: _startDate,
              time: _startTime,
              onTapDate: () => _pickDate(isStart: true),
              onTapTime: () => _pickTime(isStart: true),
            ),
            const SizedBox(height: 16),

            // ── End date & time (optional) ────────────────────
            _Label('End (optional)'),
            const SizedBox(height: 8),
            _DateTimeRow(
              date: _endDate,
              time: _endTime,
              onTapDate: () => _pickDate(isStart: false),
              onTapTime: () => _pickTime(isStart: false),
            ),
            const SizedBox(height: 20),

            // ── Description ───────────────────────────────────
            _Label('Description (optional)'),
            const SizedBox(height: 8),
            _Field(
              controller: _descCtrl,
              hint: 'Tell people more about this activity…',
              maxLines: 4,
              maxLength: 1000,
            ),
            const SizedBox(height: 20),

            // ── Max participants ──────────────────────────────
            _Label('Max participants (optional)'),
            const SizedBox(height: 8),
            _Field(
              controller: _maxCtrl,
              hint: 'e.g. 20',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared form widgets ───────────────────────────────────────────

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
        hintStyle:
            GoogleFonts.dmSans(fontSize: 14, color: AppColors.textMuted),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 18, color: AppColors.textMuted)
            : null,
        filled: true,
        fillColor: AppColors.surface,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
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
            label: date != null
                ? DateFormat('EEE, MMM d').format(date!)
                : 'Pick date',
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
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
            Icon(icon,
                size: 16,
                color: hasValue ? AppColors.primary : AppColors.textMuted),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color:
                      hasValue ? AppColors.textDark : AppColors.textMuted,
                  fontWeight:
                      hasValue ? FontWeight.w500 : FontWeight.w400,
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
