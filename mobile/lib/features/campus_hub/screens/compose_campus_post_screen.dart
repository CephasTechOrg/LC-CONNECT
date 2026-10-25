import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../../../shared/widgets/app_form_section.dart';
import '../models/campus_post.dart';
import '../providers/campus_hub_provider.dart';
import '../providers/campus_publishing_provider.dart';

part '../widgets/compose_post_form_parts.dart';
part '../widgets/compose_post_images.dart';

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
  final _urlCtrl = TextEditingController();
  late String _kind;
  late String _category;
  late String _audience;
  late String _priority;
  DateTime? _expiresAt;
  bool _loading = false;
  String? _savedPostId;
  List<CampusPostImage> _images = const [];
  final List<XFile> _pending = [];

  bool get _isEditing => widget.existing != null;
  int get _imageCount => _images.length + _pending.length;

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
    _urlCtrl.text = p?.externalUrl ?? '';
    _expiresAt = p?.expiresAt?.toLocal();
    _savedPostId = p?.id;
    _images = List<CampusPostImage>.from(p?.images ?? const []);
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
    _urlCtrl.dispose();
    super.dispose();
  }

  bool _isHttpUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  Future<void> _pickExpires() async {
    final now = DateTime.now();
    final initial = _expiresAt ?? now.add(const Duration(days: 14));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked == null || !mounted) return;
    // End of local day so "closes Sep 15" covers the whole day for students.
    setState(() => _expiresAt = DateTime(picked.year, picked.month, picked.day, 23, 59));
  }

  Future<void> _save({required bool publish}) async {
    final title = _titleCtrl.text.trim();
    final summary = _summaryCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    final isOpportunity = _kind == 'opportunity';

    if (title.isEmpty) {
      _toast('Title is required');
      return;
    }
    if (isOpportunity) {
      if (summary.isEmpty) {
        _toast('Add a brief summary for this opportunity');
        return;
      }
    } else if (body.isEmpty) {
      _toast('Title and body are required');
      return;
    }

    final url = _urlCtrl.text.trim();
    if (url.isNotEmpty && !_isHttpUrl(url)) {
      _toast('Link must be a valid http(s) URL');
      return;
    }
    if (publish) {
      final ok = await _confirmPublish();
      if (ok != true) return;
    }
    setState(() => _loading = true);
    try {
      final service = ref.read(campusPublishingServiceProvider);
      // Opportunities: title + summary (+ link). Body is filled from summary on the API.
      final resolvedBody = isOpportunity ? '' : body;
      AuthorCampusPost saved;
      if (_savedPostId != null) {
        saved = await service.updatePost(
          _savedPostId!,
          kind: _kind,
          title: title,
          summary: summary,
          body: resolvedBody,
          audience: _audience,
          priority: _priority,
          category: _category,
          externalUrl: url,
          expiresAt: _expiresAt,
        );
      } else {
        saved = await service.createPost(
          kind: _kind,
          title: title,
          summary: summary.isEmpty ? null : summary,
          body: resolvedBody,
          audience: _audience,
          priority: _priority,
          category: _category,
          externalUrl: url.isEmpty ? null : url,
          expiresAt: _expiresAt,
        );
      }
      _savedPostId = saved.id;
      for (final file in List<XFile>.from(_pending)) {
        saved = await service.uploadImage(
          saved.id,
          path: file.path,
          mimeType: _imageMime(file.path),
          filename: file.name,
        );
        // Drop each photo the moment it lands. If a later upload fails, the post stays a draft and
        // only the not-yet-uploaded photos remain queued — pressing save again retries just those,
        // never re-uploading a duplicate of one that already succeeded.
        _pending.remove(file);
        _images = saved.images;
      }
      // Only publish once every queued photo is in — a partial upload throws above and stays draft.
      if (publish && saved.isDraft) await service.publishPost(saved.id);
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

  Future<void> _pickImage() async {
    if (_imageCount >= 4 || _loading) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (picked == null || !mounted) return;
    if (_savedPostId != null) {
      setState(() => _loading = true);
      try {
        final saved = await ref.read(campusPublishingServiceProvider).uploadImage(
          _savedPostId!,
          path: picked.path,
          mimeType: _imageMime(picked.path),
          filename: picked.name,
        );
        if (!mounted) return;
        setState(() => _images = saved.images);
      } catch (e) {
        if (mounted) _toast(apiErrorMessage(e, fallback: 'Could not upload photo'));
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }
    setState(() => _pending.add(picked));
  }

  Future<void> _removeUploadedImage(CampusPostImage image) async {
    final postId = _savedPostId;
    if (postId == null || _loading) return;
    setState(() => _loading = true);
    try {
      final saved = await ref.read(campusPublishingServiceProvider).deleteImage(postId, image.id);
      if (!mounted) return;
      setState(() => _images = saved.images);
    } catch (e) {
      if (mounted) _toast(apiErrorMessage(e, fallback: 'Could not remove photo'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _removePendingImage(int index) {
    if (index < 0 || index >= _pending.length) return;
    setState(() => _pending.removeAt(index));
  }

  Future<bool?> _confirmPublish() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Publish now?'),
      content: Text(
        _priority == 'important'
            ? 'This may notify the campus audience.'
            : 'This will appear in Campus Hub for the selected audience.',
        style: AppTypography.body.copyWith(color: AppColors.textMid),
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
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isOpportunity = _kind == 'opportunity';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit post' : 'New campus post'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      // Pinned, like Create activity: publishing used to sit under eleven fields.
      bottomNavigationBar: AppFormActionBar(
        child: _Actions(
          isEditing: _isEditing,
          loading: _loading,
          onSaveDraft: () => _save(publish: false),
          onPublish: () => _save(publish: true),
          onSaveChanges: () => _save(publish: false),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.xs,
          AppSpacing.gutter,
          AppSpacing.xxxl,
        ),
        // The same shape as Create activity: required steps first, then an "Optional" group.
        children: [
          AppFormSection(
            step: 1,
            title: "What you're posting",
            children: [
              const _Label('Type'),
              _ChipWrap(options: postKindLabels, selected: _kind, onSelect: _onKindChanged),
              const SizedBox(height: AppSpacing.lg),
              const _Label('Category'),
              _ChipWrap(
                options: categoryLabelsForKind(_kind),
                selected: _category,
                onSelect: (v) => setState(() => _category = v),
              ),
            ],
          ),
          AppFormSection(
            step: 2,
            title: 'Who sees it',
            children: [
              const _Label('Audience'),
              _ChipWrap(
                options: _audiences,
                selected: _audience,
                onSelect: (v) => setState(() => _audience = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              const _Label('Priority'),
              _ChipWrap(
                options: _priorities,
                selected: _priority,
                onSelect: (v) => setState(() => _priority = v),
              ),
              if (_priority == 'important') ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Important posts may notify the audience.',
                  style: AppTypography.label.copyWith(color: AppColors.textMuted),
                ),
              ],
            ],
          ),
          AppFormSection(
            step: 3,
            title: 'Content',
            children: [
              const _Label('Title'),
              TextField(
                controller: _titleCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'A short, clear headline'),
              ),
              const SizedBox(height: AppSpacing.lg),
              _Label(isOpportunity ? 'Brief summary' : 'Summary', optional: !isOpportunity),
              TextField(
                controller: _summaryCtrl,
                textCapitalization: TextCapitalization.sentences,
                maxLines: isOpportunity ? 3 : 1,
                decoration: InputDecoration(
                  hintText: isOpportunity
                      ? 'One or two lines students see on the card'
                      : 'One line shown in the feed',
                ),
              ),
              if (_kind == 'announcement') ...[
                const SizedBox(height: AppSpacing.lg),
                _ComposePostImages(
                  uploaded: _images,
                  pending: _pending,
                  remaining: 4 - _imageCount,
                  busy: _loading,
                  onAdd: _pickImage,
                  onRemoveUploaded: _removeUploadedImage,
                  onRemovePending: _removePendingImage,
                ),
                const SizedBox(height: AppSpacing.lg),
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
              ],
            ],
          ),
          const AppFormGroupHeading(
            title: 'Optional',
            subtitle: 'Not needed to publish, but they help students act on it.',
          ),
          AppFormSection(
            children: [
              _Label(isOpportunity ? 'Application or details link' : 'External link'),
              TextField(
                controller: _urlCtrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(hintText: 'https://…'),
              ),
              const SizedBox(height: AppSpacing.lg),
              const _Label('Closes on'),
              _DeadlineTile(
                label: _expiresAt == null
                    ? 'No deadline'
                    : DateFormat('MMM d, y').format(_expiresAt!),
                hasValue: _expiresAt != null,
                onPick: _pickExpires,
                onClear: () => setState(() => _expiresAt = null),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
