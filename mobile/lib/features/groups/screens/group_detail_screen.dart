import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../messages/providers/messages_provider.dart';
import '../../safety/providers/safety_provider.dart';
import '../../safety/widgets/safety_sheet.dart';
import '../data/group_models.dart';
import '../providers/groups_provider.dart';

part '../widgets/group_member_tile.dart';
part '../widgets/group_requests_section.dart';
part '../widgets/group_admin_sheets.dart';
part '../widgets/group_detail_widgets.dart';

/// Group detail / admin screen — members, pending requests, and every admin action
/// (edit, avatar, invite, promote/demote, transfer, remove/ban, leave, delete). Which
/// controls appear is gated by `my_role`; the backend is the authority and re-checks each call.
class GroupDetailScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  final _busy = <String>{}; // user ids (or 'avatar') with an action in flight
  bool _uploadingAvatar = false;

  String get _gid => widget.groupId;
  GroupsRepository get _repo => ref.read(groupsRepositoryProvider);

  void _refreshMembers() {
    ref.invalidate(groupMembersProvider(_gid));
    ref.invalidate(groupRequestsProvider(_gid));
    ref.invalidate(groupDetailProvider(_gid));
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.dmSans(color: Colors.white)),
        backgroundColor: error ? AppColors.error : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Run [action] guarding against double-taps on [key], refresh, and report failures.
  Future<void> _guard(String key, Future<void> Function() action, {String? failure}) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      await action();
      if (!mounted) return;
      _refreshMembers();
    } catch (_) {
      _snack(failure ?? 'Something went wrong — try again', error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<bool> _confirm(String title, String message, String confirmLabel, {bool destructive = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
        content: Text(message, style: GoogleFonts.dmSans(color: AppColors.textMid)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.dmSans(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              confirmLabel,
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w700,
                color: destructive ? AppColors.error : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // ── actions ─────────────────────────────────────────────────────────────────

  Future<void> _pickAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      await _repo.uploadAvatar(
        _gid,
        path: image.path,
        mimeType: image.mimeType ?? 'image/jpeg',
        filename: image.name,
      );
      if (mounted) ref.invalidate(groupDetailProvider(_gid));
    } catch (_) {
      _snack('Could not update the photo — try again', error: true);
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _toggleMute(GroupRead group) async {
    final next = !group.myMuted;
    try {
      await _repo.setMute(_gid, next);
      if (!mounted) return;
      ref.invalidate(groupDetailProvider(_gid));
      _snack(next ? 'Notifications muted' : 'Notifications unmuted');
    } catch (_) {
      _snack('Could not update notifications — try again', error: true);
    }
  }

  void _report() {
    showReportGroupSheet(
      context: context,
      groupId: _gid,
      safetyService: ref.read(safetyServiceProvider),
    );
  }

  Future<void> _edit(GroupRead group) async {
    final saved = await showGroupEditSheet(context, ref, group);
    if (saved && mounted) {
      ref.invalidate(groupDetailProvider(_gid));
      _snack('Group updated');
    }
  }

  Future<void> _invite() async {
    final invitedName = await showInviteSheet(context, ref, _gid);
    if (invitedName != null && mounted) _snack('Invited $invitedName');
  }

  void _approve(String userId) => _guard(userId, () => _repo.approve(_gid, userId), failure: 'Could not approve');
  void _reject(String userId) => _guard(userId, () => _repo.reject(_gid, userId), failure: 'Could not reject');

  void _changeRole(GroupMember m, String role) => _guard(
        m.userId,
        () => _repo.changeRole(_gid, m.userId, role),
        failure: 'Could not change role',
      );

  Future<void> _transfer(GroupMember m) async {
    if (!await _confirm(
      'Transfer ownership?',
      'Make ${m.nameOrFallback} the owner? You will become an admin.',
      'Transfer',
      destructive: true,
    )) {
      return;
    }
    await _guard(m.userId, () => _repo.transferOwnership(_gid, m.userId), failure: 'Could not transfer');
  }

  Future<void> _remove(GroupMember m, {required bool ban}) async {
    if (!await _confirm(
      ban ? 'Ban member?' : 'Remove member?',
      ban
          ? '${m.nameOrFallback} will be removed and cannot rejoin.'
          : 'Remove ${m.nameOrFallback} from the group?',
      ban ? 'Ban' : 'Remove',
      destructive: true,
    )) {
      return;
    }
    await _guard(m.userId, () => _repo.removeMember(_gid, m.userId, ban: ban), failure: 'Could not remove');
  }

  Future<void> _leave(GroupRead group) async {
    if (!await _confirm('Leave group?', 'Leave ${group.name}? You can rejoin later if it stays open.', 'Leave',
        destructive: true)) {
      return;
    }
    try {
      await _repo.leave(_gid);
      if (!mounted) return;
      _afterExit();
    } catch (_) {
      _snack('Could not leave — try again', error: true);
    }
  }

  Future<void> _delete(GroupRead group) async {
    if (!await _confirm('Delete group?', 'Permanently delete ${group.name} and all its messages? This cannot be undone.',
        'Delete', destructive: true)) {
      return;
    }
    try {
      await _repo.delete(_gid);
      if (!mounted) return;
      _afterExit();
    } catch (_) {
      _snack('Could not delete — try again', error: true);
    }
  }

  /// After leaving/deleting: refresh the lists that showed this group and return to Messages.
  void _afterExit() {
    ref.invalidate(myGroupsProvider);
    ref.invalidate(threadsNotifierProvider);
    context.go('/messages');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(groupDetailProvider(_gid));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('Group info', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: AppColors.textDark)),
        iconTheme: const IconThemeData(color: AppColors.textDark),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ErrorRetry(onRetry: () => ref.invalidate(groupDetailProvider(_gid))),
        data: (group) => _body(group),
      ),
    );
  }

  Widget _body(GroupRead group) {
    return ListView(
      children: [
        _GroupHeader(
          group: group,
          uploading: _uploadingAvatar,
          onEditAvatar: group.iCanManage ? _pickAvatar : null,
        ),
        if (group.iCanManage)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(child: _ActionButton(icon: Icons.edit_outlined, label: 'Edit', onTap: () => _edit(group))),
                const SizedBox(width: 10),
                Expanded(child: _ActionButton(icon: Icons.person_add_alt_1_outlined, label: 'Invite', onTap: _invite)),
              ],
            ),
          ),
        if (group.isMember)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: _MuteRow(muted: group.myMuted, onChanged: (_) => _toggleMute(group)),
          ),
        if (group.iCanManage)
          _RequestsSection(groupId: _gid, busy: _busy, onApprove: _approve, onReject: _reject),
        _MembersList(
          groupId: _gid,
          myRole: group.myRole,
          busy: _busy,
          onChangeRole: _changeRole,
          onTransfer: _transfer,
          onRemove: (m) => _remove(m, ban: false),
          onBan: (m) => _remove(m, ban: true),
          onRetry: () => ref.invalidate(groupMembersProvider(_gid)),
        ),
        const SizedBox(height: 16),
        _FooterActions(
          group: group,
          onReport: _report,
          onLeave: () => _leave(group),
          onDelete: () => _delete(group),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
