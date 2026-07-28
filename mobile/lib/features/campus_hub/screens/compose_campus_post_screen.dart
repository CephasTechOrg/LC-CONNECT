import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../models/campus_post.dart';
import '../providers/campus_hub_provider.dart';
import '../providers/campus_publishing_provider.dart';

class ComposeCampusPostScreen extends ConsumerStatefulWidget {
  const ComposeCampusPostScreen({super.key});

  @override
  ConsumerState<ComposeCampusPostScreen> createState() => _ComposeCampusPostScreenState();
}

class _ComposeCampusPostScreenState extends ConsumerState<ComposeCampusPostScreen> {
  final _titleCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _kind = 'update';
  String _audience = 'all';
  String _priority = 'normal';
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save({required bool publish}) async {
    if (_titleCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and body are required')),
      );
      return;
    }
    if (publish) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Publish now?'),
          content: Text(
            _priority == 'important'
                ? 'This may notify the campus audience.'
                : 'This will appear in Campus Hub for the selected audience.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publish')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _loading = true);
    try {
      final service = ref.read(campusPublishingServiceProvider);
      final draft = await service.createPost(
        kind: _kind,
        title: _titleCtrl.text.trim(),
        summary: _summaryCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
        audience: _audience,
        priority: _priority,
      );
      if (publish) {
        await service.publishPost(draft.id);
      }
      ref.invalidate(myCampusPostsProvider);
      ref.invalidate(campusHubOverviewProvider);
      ref.invalidate(campusPostsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(publish ? 'Published' : 'Draft saved')),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Could not save post'))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  onPressed: () => context.pop(),
                ),
                Text(
                  'New campus post',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Type', style: _label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: postKindLabels.entries
                  .where((e) => e.key != 'alert')
                  .map(
                    (e) => ChoiceChip(
                      label: Text(e.value),
                      selected: _kind == e.key,
                      onSelected: (_) => setState(() => _kind = e.key),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            Text('Audience', style: _label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in {'all': 'Everyone', 'students': 'Students', 'staff': 'Staff'}.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _audience == entry.key,
                    onSelected: (_) => setState(() => _audience = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Priority', style: _label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in {'normal': 'Normal', 'important': 'Important'}.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _priority == entry.key,
                    onSelected: (_) => setState(() => _priority = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _summaryCtrl,
              decoration: const InputDecoration(labelText: 'Summary (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyCtrl,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Body'),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _loading ? null : () => _save(publish: false),
              child: Text(_loading ? 'Saving…' : 'Save draft'),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _loading ? null : () => _save(publish: true),
              child: const Text('Publish now'),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle get _label => GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
      );
}
