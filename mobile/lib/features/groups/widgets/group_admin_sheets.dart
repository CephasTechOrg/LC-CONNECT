part of '../screens/group_detail_screen.dart';

// ── Edit group settings ──────────────────────────────────────────────────────

/// Bottom sheet to edit a group's name/description/visibility/join policy/capacity.
/// Returns `true` if the group was saved. Only changed fields are sent (PATCH semantics).
Future<bool> showGroupEditSheet(BuildContext context, WidgetRef ref, GroupRead group) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _GroupEditSheet(group: group),
  );
  return saved ?? false;
}

class _GroupEditSheet extends ConsumerStatefulWidget {
  final GroupRead group;
  const _GroupEditSheet({required this.group});

  @override
  ConsumerState<_GroupEditSheet> createState() => _GroupEditSheetState();
}

class _GroupEditSheetState extends ConsumerState<_GroupEditSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.group.name);
  late final TextEditingController _description =
      TextEditingController(text: widget.group.description ?? '');
  late final TextEditingController _maxMembers =
      TextEditingController(text: widget.group.maxMembers?.toString() ?? '');
  late String _visibility = widget.group.visibility;
  late String _joinPolicy = widget.group.joinPolicy;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _maxMembers.dispose();
    super.dispose();
  }

  Map<String, dynamic> _changes() {
    final g = widget.group;
    final changes = <String, dynamic>{};
    final name = _name.text.trim();
    if (name.isNotEmpty && name != g.name) changes['name'] = name;
    final desc = _description.text.trim();
    if (desc != (g.description ?? '')) changes['description'] = desc.isEmpty ? null : desc;
    if (_visibility != g.visibility) changes['visibility'] = _visibility;
    if (_joinPolicy != g.joinPolicy) changes['join_policy'] = _joinPolicy;
    final max = int.tryParse(_maxMembers.text.trim());
    if (max != g.maxMembers) changes['max_members'] = max;
    return changes;
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      _snack('Name must be at least 2 characters', error: true);
      return;
    }
    final changes = _changes();
    if (changes.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(groupsRepositoryProvider).update(widget.group.id, changes);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Could not save — try again', error: true);
      }
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.dmSans(color: Colors.white)),
        backgroundColor: error ? AppColors.error : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Edit group', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 16),
            _label('Name'),
            TextField(controller: _name, decoration: _dec('Group name')),
            const SizedBox(height: 14),
            _label('Description'),
            TextField(controller: _description, maxLines: 3, decoration: _dec('What is this group about?')),
            const SizedBox(height: 14),
            _label('Who can find it'),
            _dropdown(_visibility, const {'public': 'Public', 'unlisted': 'Unlisted', 'private': 'Private'},
                (v) => setState(() => _visibility = v)),
            const SizedBox(height: 14),
            _label('How people join'),
            _dropdown(_joinPolicy, const {'open': 'Anyone can join', 'approval': 'Requires approval', 'invite': 'Invite only'},
                (v) => setState(() => _joinPolicy = v)),
            const SizedBox(height: 14),
            _label('Member limit (optional)'),
            TextField(controller: _maxMembers, keyboardType: TextInputType.number, decoration: _dec('No limit')),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Save changes', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMid)),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmSans(color: AppColors.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
      );

  Widget _dropdown(String value, Map<String, String> options, ValueChanged<String> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: GoogleFonts.dmSans(color: AppColors.textDark, fontSize: 14),
          items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => v != null ? onChanged(v) : null,
        ),
      ),
    );
  }
}

// ── Invite people (from your conversations) ──────────────────────────────────

/// Bottom sheet to invite someone you already message into the group. Returns the invited
/// person's display name on success, or null. (Group members already present are hidden.)
Future<String?> showInviteSheet(BuildContext context, WidgetRef ref, String groupId) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _InviteSheet(groupId: groupId),
  );
}

class _InviteSheet extends ConsumerStatefulWidget {
  final String groupId;
  const _InviteSheet({required this.groupId});

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  final _inviting = <String>{};

  Future<void> _invite(String userId, String name) async {
    if (_inviting.contains(userId)) return;
    setState(() => _inviting.add(userId));
    try {
      await ref.read(groupsRepositoryProvider).invite(widget.groupId, userId);
      if (mounted) Navigator.pop(context, name);
    } catch (e) {
      if (mounted) {
        setState(() => _inviting.remove(userId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                apiErrorMessage(e, fallback: 'Could not invite — they may already be in the group'),
                style: GoogleFonts.dmSans(color: Colors.white)),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(threadsNotifierProvider);
    // Exclude people already in the group so we never offer an invite the backend would 409.
    final memberIds = ref.watch(groupMembersProvider(widget.groupId)).asData?.value
            .map((m) => m.userId)
            .toSet() ??
        const <String>{};
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Invite people', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 4),
          Text('People you message', style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted)),
          const SizedBox(height: 12),
          async.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (_, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load your contacts', style: GoogleFonts.dmSans(color: AppColors.textMuted)),
            ),
            data: (threads) {
              final connections = threads.where((t) => !t.isGroup && t.partner != null).toList();
              final people =
                  connections.where((t) => !memberIds.contains(t.partner!.userId)).toList();
              if (people.isEmpty) {
                // Distinguish "no connections at all" from "all your connections are already in".
                final message = connections.isEmpty
                    ? 'No one to invite yet — connect with people first.'
                    : 'Everyone you know is already in this group.';
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(message, style: GoogleFonts.dmSans(color: AppColors.textMuted)),
                );
              }
              return Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: people.length,
                  itemBuilder: (_, i) {
                    final p = people[i].partner!;
                    final name = p.displayName ?? 'LC Student';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: AvatarWidget(imageUrl: p.avatarUrl, size: 40, cacheScope: p.userId),
                      title: Text(name, style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, color: AppColors.textDark)),
                      subtitle: p.major != null
                          ? Text(p.major!, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted))
                          : null,
                      trailing: _inviting.contains(p.userId)
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : TextButton(
                              onPressed: () => _invite(p.userId, name),
                              child: Text('Invite',
                                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: AppColors.primary)),
                            ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
