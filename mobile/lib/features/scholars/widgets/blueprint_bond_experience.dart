part of '../screens/blueprint_bond_screen.dart';

const _kMaxExperienceEntries = 5;

/// Internship / experience entries + add button — the body of the Experience card.
class _InternshipSection extends StatelessWidget {
  final List<ScholarInternship> items;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int index, ScholarInternship value) onEdit;

  const _InternshipSection({
    required this.items,
    required this.onAdd,
    required this.onRemove,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return _EntryList(
      emptyText: 'No experience added yet.',
      addLabel: 'Add internship',
      canAdd: items.length < _kMaxExperienceEntries,
      onAdd: onAdd,
      entries: [
        for (var i = 0; i < items.length; i++)
          _ExperienceCard(
            title: items[i].title,
            subtitle: items[i].organization,
            meta: _internshipMeta(items[i]),
            description: items[i].description,
            onEdit: () => onEdit(i, items[i]),
            onRemove: () => onRemove(i),
          ),
      ],
    );
  }

  static String? _internshipMeta(ScholarInternship e) {
    final start = e.startDate?.trim();
    final end = e.isCurrent ? 'Present' : e.endDate?.trim();
    if ((start == null || start.isEmpty) && (end == null || end.isEmpty)) return null;
    if (start == null || start.isEmpty) return end;
    if (end == null || end.isEmpty) return start;
    return '$start – $end';
  }
}

/// Project entries + add button — the body of the Projects card.
class _ProjectSection extends StatelessWidget {
  final List<ScholarProject> items;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int index, ScholarProject value) onEdit;

  const _ProjectSection({
    required this.items,
    required this.onAdd,
    required this.onRemove,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return _EntryList(
      emptyText: 'No projects added yet.',
      addLabel: 'Add project',
      canAdd: items.length < _kMaxExperienceEntries,
      onAdd: onAdd,
      entries: [
        for (var i = 0; i < items.length; i++)
          _ExperienceCard(
            title: items[i].name,
            subtitle: items[i].role,
            meta: items[i].url,
            description: items[i].description,
            onEdit: () => onEdit(i, items[i]),
            onRemove: () => onRemove(i),
          ),
      ],
    );
  }
}

class _EntryList extends StatelessWidget {
  final String emptyText;
  final String addLabel;
  final bool canAdd;
  final VoidCallback onAdd;
  final List<Widget> entries;

  const _EntryList({
    required this.emptyText,
    required this.addLabel,
    required this.canAdd,
    required this.onAdd,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              emptyText,
              style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
            ),
          ),
        for (final entry in entries) ...[
          entry,
          const SizedBox(height: AppSpacing.sm),
        ],
        if (entries.isNotEmpty) const SizedBox(height: AppSpacing.xs),
        _AddEntryButton(label: addLabel, onTap: canAdd ? onAdd : null),
      ],
    );
  }
}

class _ExperienceCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? meta;
  final String? description;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _ExperienceCard({
    required this.title,
    this.subtitle,
    this.meta,
    this.description,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, 0, AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!, style: AppTypography.bodySmall.copyWith(color: AppColors.textMid)),
                if (meta != null && meta!.isNotEmpty)
                  Text(meta!, style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                if (description != null && description!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    description!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textMid, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textMuted),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

Future<ScholarInternship?> showInternshipEditor(
  BuildContext context, {
  ScholarInternship? initial,
}) async {
  final titleCtrl = TextEditingController(text: initial?.title ?? '');
  final orgCtrl = TextEditingController(text: initial?.organization ?? '');
  final startCtrl = TextEditingController(text: initial?.startDate ?? '');
  final endCtrl = TextEditingController(text: initial?.endDate ?? '');
  final descCtrl = TextEditingController(text: initial?.description ?? '');
  var isCurrent = initial?.isCurrent ?? false;

  final result = await showModalBottomSheet<ScholarInternship>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (ctx, setModal) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    initial == null ? 'Add internship' : 'Edit internship',
                    style: AppTypography.title.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Field(label: 'Role / title', controller: titleCtrl),
                  const SizedBox(height: 12),
                  _Field(label: 'Organization', controller: orgCtrl),
                  const SizedBox(height: 12),
                  _Field(label: 'Start (e.g. Jun 2024)', controller: startCtrl, hint: 'Optional'),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Currently in this role', style: AppTypography.body.copyWith(color: AppColors.textDark)),
                    value: isCurrent,
                    activeTrackColor: AppColors.primary,
                    onChanged: (v) => setModal(() => isCurrent = v),
                  ),
                  if (!isCurrent) ...[
                    _Field(label: 'End (e.g. Aug 2024)', controller: endCtrl, hint: 'Optional'),
                    const SizedBox(height: 12),
                  ],
                  _Field(label: 'Description', controller: descCtrl, maxLines: 3, hint: 'Optional'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      final title = titleCtrl.text.trim();
                      final org = orgCtrl.text.trim();
                      if (title.isEmpty || org.isEmpty) return;
                      Navigator.of(ctx).pop(ScholarInternship(
                        title: title,
                        organization: org,
                        startDate: startCtrl.text.trim().isEmpty ? null : startCtrl.text.trim(),
                        endDate: isCurrent
                            ? null
                            : (endCtrl.text.trim().isEmpty ? null : endCtrl.text.trim()),
                        isCurrent: isCurrent,
                        description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                      ));
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(kMinTouchTarget),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
                    ),
                    child: Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );

  titleCtrl.dispose();
  orgCtrl.dispose();
  startCtrl.dispose();
  endCtrl.dispose();
  descCtrl.dispose();
  return result;
}

Future<ScholarProject?> showProjectEditor(
  BuildContext context, {
  ScholarProject? initial,
}) async {
  final nameCtrl = TextEditingController(text: initial?.name ?? '');
  final roleCtrl = TextEditingController(text: initial?.role ?? '');
  final urlCtrl = TextEditingController(text: initial?.url ?? '');
  final descCtrl = TextEditingController(text: initial?.description ?? '');

  final result = await showModalBottomSheet<ScholarProject>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                initial == null ? 'Add project' : 'Edit project',
                style: AppTypography.title.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 14),
              _Field(label: 'Project name', controller: nameCtrl),
              const SizedBox(height: 12),
              _Field(label: 'Your role', controller: roleCtrl, hint: 'Optional'),
              const SizedBox(height: 12),
              _Field(label: 'Link (URL)', controller: urlCtrl, hint: 'Optional'),
              const SizedBox(height: 12),
              _Field(label: 'Description', controller: descCtrl, maxLines: 3, hint: 'Optional'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  Navigator.of(ctx).pop(ScholarProject(
                    name: name,
                    role: roleCtrl.text.trim().isEmpty ? null : roleCtrl.text.trim(),
                    url: urlCtrl.text.trim().isEmpty ? null : urlCtrl.text.trim(),
                    description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  ));
                },
                style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(kMinTouchTarget),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
                    ),
                child: Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    },
  );

  nameCtrl.dispose();
  roleCtrl.dispose();
  urlCtrl.dispose();
  descCtrl.dispose();
  return result;
}
