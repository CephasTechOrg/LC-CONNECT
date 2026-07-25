import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/activities_provider.dart';

part '../widgets/activity_form_fields.dart';

const _categories = [
  ('study', 'Study', Icons.menu_book_outlined),
  ('sports', 'Sports', Icons.sports_outlined),
  ('social', 'Social', Icons.people_outline),
  ('culture', 'Culture', Icons.palette_outlined),
];

class CreateActivityScreen extends ConsumerStatefulWidget {
  /// When set, the screen edits this activity instead of creating a new one.
  final Activity? existing;
  const CreateActivityScreen({super.key, this.existing});

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
  XFile? _banner; // newly picked banner (not yet uploaded)
  bool _submitting = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    if (a != null) {
      _titleCtrl.text = a.title;
      _locationCtrl.text = a.location;
      _descCtrl.text = a.description ?? '';
      _maxCtrl.text = a.maxParticipants?.toString() ?? '';
      _category = a.category;
      final start = a.startTime.toLocal();
      _startDate = start;
      _startTime = TimeOfDay.fromDateTime(start);
      final end = a.endTime?.toLocal();
      if (end != null) {
        _endDate = end;
        _endTime = TimeOfDay.fromDateTime(end);
      }
    }
  }

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

  Future<void> _pickBanner() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 900,
      imageQuality: 85,
    );
    if (image != null && mounted) setState(() => _banner = image);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    final notifier = ref.read(activitiesNotifierProvider.notifier);
    try {
      final startDt = _combine(_startDate!, _startTime!);
      final endDt = (_endDate != null && _endTime != null) ? _combine(_endDate!, _endTime!) : null;
      final maxP = _maxCtrl.text.trim().isNotEmpty ? int.tryParse(_maxCtrl.text.trim()) : null;
      final title = _titleCtrl.text.trim();
      final location = _locationCtrl.text.trim();
      final description = _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null;

      final String activityId;
      if (_isEdit) {
        final updated = await notifier.edit(widget.existing!.id, {
          'title': title,
          'category': _category,
          'location': location,
          'start_time': startDt.toUtc().toIso8601String(),
          'end_time': endDt?.toUtc().toIso8601String(),
          'description': description,
          'max_participants': maxP,
        });
        activityId = updated.id;
      } else {
        final created = await notifier.create(
          title: title, category: _category!, location: location,
          startTime: startDt, endTime: endDt, description: description, maxParticipants: maxP,
        );
        activityId = created.id;
      }
      // Banner is a separate multipart upload; a failure keeps the activity (add it later).
      if (_banner != null) {
        try {
          await notifier.uploadBanner(activityId,
              path: _banner!.path, mimeType: _banner!.mimeType ?? 'image/jpeg', filename: _banner!.name);
        } catch (_) {/* keep the activity without the banner */}
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      _snack(_isEdit ? 'Activity updated' : 'Activity created!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack(apiErrorMessage(e, fallback: 'Could not save the activity. Please try again.'), error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.dmSans()),
      backgroundColor: error ? AppColors.error : null,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Activity' : 'Create Activity'),
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
                    _isEdit ? 'Save changes' : 'Create Activity',
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
            // ── Banner (optional) ─────────────────────────────
            _BannerPicker(
              picked: _banner,
              existingUrl: widget.existing?.bannerUrl,
              onTap: _submitting ? null : _pickBanner,
            ),
            const SizedBox(height: 20),

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
