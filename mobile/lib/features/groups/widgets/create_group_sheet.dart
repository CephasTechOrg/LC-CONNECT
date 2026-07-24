import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../data/group_models.dart';
import '../providers/groups_provider.dart';

/// Bottom sheet to create a group. Returns the created group, or null if cancelled.
Future<GroupRead?> showCreateGroupSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<GroupRead>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: const _CreateGroupForm(),
    ),
  );
}

class _CreateGroupForm extends ConsumerStatefulWidget {
  const _CreateGroupForm();
  @override
  ConsumerState<_CreateGroupForm> createState() => _CreateGroupFormState();
}

class _CreateGroupFormState extends ConsumerState<_CreateGroupForm> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String _category = 'club';
  String _joinPolicy = 'open';
  String _visibility = 'public';
  XFile? _avatar;
  bool _submitting = false;
  String? _error;

  static const _categories = {'club': 'Club', 'housing': 'Housing', 'class': 'Class', 'interest': 'Interest'};
  static const _policies = {'open': 'Anyone can join', 'approval': 'Approve requests', 'invite': 'Invite only'};
  static const _visibilities = {'public': 'Public', 'unlisted': 'Unlisted', 'private': 'Private'};

  String get _visibilityHint => switch (_visibility) {
        'unlisted' => 'Not shown in discovery — shareable by invite only.',
        'private' => 'Hidden from everyone; members join by invite only.',
        _ => 'Anyone can find this group in discovery.',
      };

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (image != null && mounted) setState(() => _avatar = image);
  }

  Future<void> _submit() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Name must be at least 2 characters');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final repo = ref.read(groupsRepositoryProvider);
      var group = await repo.create(
        name: _name.text.trim(),
        category: _category,
        visibility: _visibility,
        joinPolicy: _joinPolicy,
        description: _description.text.trim(),
      );
      // Avatar is a separate multipart upload. If it fails the group still exists, so keep it
      // (the owner can set a photo later from the group's info screen) rather than fail create.
      if (_avatar != null) {
        try {
          group = await repo.uploadAvatar(
            group.id,
            path: _avatar!.path,
            mimeType: _avatar!.mimeType ?? 'image/jpeg',
            filename: _avatar!.name,
          );
        } catch (_) {/* keep the created group without the avatar */}
      }
      if (mounted) Navigator.of(context).pop(group);
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Could not create the group. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          Text('Create a group', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 16),
          Center(child: _avatarPicker()),
          const SizedBox(height: 16),
          _field(_name, 'Group name', autofocus: true),
          const SizedBox(height: 12),
          _field(_description, 'Description (optional)', maxLines: 2),
          const SizedBox(height: 16),
          _label('Category'),
          _chips(_categories, _category, (v) => setState(() => _category = v)),
          const SizedBox(height: 16),
          _label('Who can join'),
          _chips(_policies, _joinPolicy, (v) => setState(() => _joinPolicy = v)),
          const SizedBox(height: 16),
          _label('Visibility'),
          _chips(_visibilities, _visibility, (v) => setState(() => _visibility = v)),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _visibilityHint,
              style: GoogleFonts.dmSans(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: GoogleFonts.dmSans(fontSize: 12, color: Colors.red.shade600)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Create group', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarPicker() => GestureDetector(
        onTap: _submitting ? null : _pickAvatar,
        child: Stack(
          children: [
            Container(
              width: 76,
              height: 76,
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
              child: _avatar != null
                  ? Image.file(File(_avatar!.path), width: 76, height: 76, fit: BoxFit.cover)
                  : const Icon(Icons.groups_outlined, size: 30, color: AppColors.primary),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt_rounded, size: 13, color: Colors.white),
              ),
            ),
          ],
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMid)),
      );

  Widget _field(TextEditingController c, String hint, {int maxLines = 1, bool autofocus = false}) => TextField(
        controller: c,
        maxLines: maxLines,
        autofocus: autofocus,
        style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textDark),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textMuted),
          filled: true,
          fillColor: AppColors.background,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary)),
        ),
      );

  Widget _chips(Map<String, String> options, String selected, ValueChanged<String> onSelect) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in options.entries)
            GestureDetector(
              onTap: () => onSelect(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected == e.key ? AppColors.primary : AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selected == e.key ? AppColors.primary : AppColors.border),
                ),
                child: Text(
                  e.value,
                  style: GoogleFonts.dmSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected == e.key ? Colors.white : AppColors.textMid,
                  ),
                ),
              ),
            ),
        ],
      );
}
