import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../models/campus_post.dart';
import '../providers/campus_hub_provider.dart';
import '../providers/campus_publishing_provider.dart';

/// Create or edit a campus post. Pass `existing` to edit. One clean form — grouped selectors up
/// top, then the content fields — styled to match the rest of the app (no raw Material chips).
class ComposeCampusPostScreen extends ConsumerStatefulWidget {
  final AuthorCampusPost? existing;
  const ComposeCampusPostScreen({super.key, this.existing});

  @override
  ConsumerState<ComposeCampusPostScreen> createState() => _ComposeCampusPostScreenState();
}

class _ComposeCampusPostScreenState extends ConsumerState<ComposeCampusPostScreen> {
  final _titleCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  late String _kind;
  late String _category;
  late String _audience;
  late String _priority;
  bool _loading = false;

  bool get _isEditing => widget.existing != null;

  static const _audiences = {'all': 'Everyone', 'students': 'Students', 'staff': 'Staff'};
  static const _priorities = {'normal': 'Normal', 'important': 'Important'};

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _kind = p?.kind ?? 'announcement';
    // Category vocab depends on kind — fall back to that kind's first category if the existing
    // post has none (e.g. an older post created before categories existed).
    _category = p?.category ?? categoryLabelsForKind(_kind).keys.first;
    _audience = p?.audience ?? 'all';
    _priority = p?.priority ?? 'normal';
    _titleCtrl.text = p?.title ?? '';
    _summaryCtrl.text = p?.summary ?? '';
    _bodyCtrl.text = p?.body ?? '';
  }

  /// Switching type changes the category vocabulary — reset to that vocabulary's first option so
  /// _category is never a stale value from the other kind (e.g. "Internships" on an Announcement).
  void _onKindChanged(String kind) {
    setState(() {
      _kind = kind;
      _category = categoryLabelsForKind(kind).keys.first;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save({required bool publish}) async {
    if (_titleCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      _toast('Title and body are required');
      return;
    }
    if (publish) {
      final ok = await _confirmPublish();
      if (ok != true) return;
    }
    setState(() => _loading = true);
    try {
      final service = ref.read(campusPublishingServiceProvider);
      final title = _titleCtrl.text.trim();
      final summary = _summaryCtrl.text.trim();
      final body = _bodyCtrl.text.trim();
      if (_isEditing) {
        await service.updatePost(widget.existing!.id,
            kind: _kind, title: title, summary: summary, body: body, audience: _audience, priority: _priority,
            category: _category);
      } else {
        final draft = await service.createPost(
            kind: _kind, title: title, summary: summary, body: body, audience: _audience, priority: _priority,
            category: _category);
        if (publish) await service.publishPost(draft.id);
      }
      _invalidateFeeds();
      if (!mounted) return;
      _toast(_isEditing ? 'Changes saved' : (publish ? 'Published' : 'Draft saved'));
      context.pop();
    } catch (e) {
      if (mounted) _toast(apiErrorMessage(e, fallback: 'Could not save post'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool?> _confirmPublish() => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Publish now?', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
          content: Text(
            _priority == 'important'
                ? 'This may notify the campus audience.'
                : 'This will appear in Campus Hub for the selected audience.',
            style: GoogleFonts.dmSans(color: AppColors.textMid),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publish')),
          ],
        ),
      );

  void _invalidateFeeds() {
    ref.invalidate(myCampusPostsProvider);
    ref.invalidate(campusHubOverviewProvider);
    ref.invalidate(campusPostsProvider);
  }

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.dmSans()),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(title: _isEditing ? 'Edit post' : 'New campus post'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  const _Label('Type'),
                  _ChipWrap(
                    options: postKindLabels,
                    selected: _kind,
                    onSelect: _onKindChanged,
                  ),
                  const SizedBox(height: 20),
                  const _Label('Category'),
                  _ChipWrap(
                    options: categoryLabelsForKind(_kind),
                    selected: _category,
                    onSelect: (v) => setState(() => _category = v),
                  ),
                  const SizedBox(height: 20),
                  const _Label('Audience'),
                  _ChipWrap(options: _audiences, selected: _audience, onSelect: (v) => setState(() => _audience = v)),
                  const SizedBox(height: 20),
                  const _Label('Priority'),
                  _ChipWrap(options: _priorities, selected: _priority, onSelect: (v) => setState(() => _priority = v)),
                  const SizedBox(height: 24),
                  const _Label('Title'),
                  TextField(
                    controller: _titleCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'A short, clear headline'),
                  ),
                  const SizedBox(height: 16),
                  const _Label('Summary', optional: true),
                  TextField(
                    controller: _summaryCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'One line shown in the feed'),
                  ),
                  const SizedBox(height: 16),
                  const _Label('Details'),
                  TextField(
                    controller: _bodyCtrl,
                    maxLines: 7,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Write the full message…',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _Actions(
                    isEditing: _isEditing,
                    loading: _loading,
                    onSaveDraft: () => _save(publish: false),
                    onPublish: () => _save(publish: true),
                    onSaveChanges: () => _save(publish: false),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String title;
  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final bool optional;
  const _Label(this.text, {this.optional = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(text,
              style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          if (optional) ...[
            const SizedBox(width: 6),
            Text('optional', style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  final Map<String, String> options;
  final String selected;
  final ValueChanged<String> onSelect;
  const _ChipWrap({required this.options, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in options.entries)
          AppFilterChip(label: e.value, selected: selected == e.key, onTap: () => onSelect(e.key)),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  final bool isEditing;
  final bool loading;
  final VoidCallback onSaveDraft;
  final VoidCallback onPublish;
  final VoidCallback onSaveChanges;
  const _Actions({
    required this.isEditing,
    required this.loading,
    required this.onSaveDraft,
    required this.onPublish,
    required this.onSaveChanges,
  });

  @override
  Widget build(BuildContext context) {
    if (isEditing) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: FilledButton(
          onPressed: loading ? null : onSaveChanges,
          child: Text(loading ? 'Saving…' : 'Save changes',
              style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: loading ? null : onPublish,
            child: Text(loading ? 'Working…' : 'Publish now',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: loading ? null : onSaveDraft,
            child: Text('Save as draft',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.primary)),
          ),
        ),
      ],
    );
  }
}
