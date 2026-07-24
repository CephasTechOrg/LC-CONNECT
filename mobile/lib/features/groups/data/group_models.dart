/// Group models mirroring the backend `/groups` API (GroupSummary / GroupRead).
library;

class GroupSummary {
  final String id;
  final String name;
  final String? avatarUrl;
  final String category; // club | housing | class | interest
  final String visibility; // public | unlisted | private
  final String joinPolicy; // open | approval | invite
  final int memberCount;
  final int? maxMembers;
  final String? myStatus; // null | requested | invited | active | banned

  const GroupSummary({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.category,
    required this.visibility,
    required this.joinPolicy,
    required this.memberCount,
    this.maxMembers,
    this.myStatus,
  });

  factory GroupSummary.fromJson(Map<String, dynamic> j) => GroupSummary(
        id: j['id'] as String,
        name: j['name'] as String,
        avatarUrl: j['avatar_url'] as String?,
        category: j['category'] as String,
        visibility: j['visibility'] as String,
        joinPolicy: j['join_policy'] as String,
        memberCount: (j['member_count'] as num).toInt(),
        maxMembers: (j['max_members'] as num?)?.toInt(),
        myStatus: j['my_status'] as String?,
      );

  bool get isMember => myStatus == 'active';
  bool get isPending => myStatus == 'requested';

  bool get isInvited => myStatus == 'invited';

  /// The join button label given the group's policy + my membership state.
  String get actionLabel {
    if (isMember) return 'Joined';
    if (isPending) return 'Pending';
    if (isInvited) return 'Invited'; // accept/decline lives in the Pending invites section
    return switch (joinPolicy) {
      'approval' => 'Request',
      'invite' => 'Invite only',
      _ => 'Join',
    };
  }

  bool get actionEnabled => !isMember && !isPending && !isInvited && joinPolicy != 'invite';

  GroupSummary copyWith({String? myStatus, int? memberCount}) => GroupSummary(
        id: id,
        name: name,
        avatarUrl: avatarUrl,
        category: category,
        visibility: visibility,
        joinPolicy: joinPolicy,
        memberCount: memberCount ?? this.memberCount,
        maxMembers: maxMembers,
        myStatus: myStatus ?? this.myStatus,
      );
}

class GroupRead extends GroupSummary {
  final String? description;
  final String ownerId;
  final String conversationId;
  final String? myRole; // null | member | admin | owner

  const GroupRead({
    required super.id,
    required super.name,
    super.avatarUrl,
    required super.category,
    required super.visibility,
    required super.joinPolicy,
    required super.memberCount,
    super.maxMembers,
    super.myStatus,
    this.description,
    required this.ownerId,
    required this.conversationId,
    this.myRole,
  });

  factory GroupRead.fromJson(Map<String, dynamic> j) => GroupRead(
        id: j['id'] as String,
        name: j['name'] as String,
        avatarUrl: j['avatar_url'] as String?,
        category: j['category'] as String,
        visibility: j['visibility'] as String,
        joinPolicy: j['join_policy'] as String,
        memberCount: (j['member_count'] as num).toInt(),
        maxMembers: (j['max_members'] as num?)?.toInt(),
        myStatus: j['my_status'] as String?,
        description: j['description'] as String?,
        ownerId: j['owner_id'] as String,
        conversationId: j['conversation_id'] as String,
        myRole: j['my_role'] as String?,
      );

  bool get iAmOwner => myRole == 'owner';

  /// Admin+ — may invite, approve/reject requests, edit settings, change the avatar,
  /// and remove/ban members (mirrors the backend `_MIN_ROLE`; the server is authoritative).
  bool get iCanManage => myRole == 'owner' || myRole == 'admin';
}

/// A single group member (or pending request/invite), as returned by `/groups/{id}/members`
/// and `/groups/{id}/requests`. The profile fields are flattened from the nested `profile`.
class GroupMember {
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final String? major;
  final String role; // member | admin | owner
  final String status; // active | requested | invited | banned | removed
  final DateTime joinedAt;

  const GroupMember({
    required this.userId,
    this.displayName,
    this.avatarUrl,
    this.major,
    required this.role,
    required this.status,
    required this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> j) {
    final p = j['profile'] as Map<String, dynamic>?;
    return GroupMember(
      userId: j['user_id'] as String,
      displayName: p?['display_name'] as String?,
      avatarUrl: p?['avatar_url'] as String?,
      major: p?['major'] as String?,
      role: j['role'] as String,
      status: j['status'] as String,
      joinedAt: DateTime.parse(j['joined_at'] as String),
    );
  }

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin';
  String get nameOrFallback => displayName ?? 'LC Student';
}

/// Role ordering: owner (2) outranks admin (1) outranks member (0). Unknown roles sort lowest.
int roleRank(String role) => const {'member': 0, 'admin': 1, 'owner': 2}[role] ?? -1;

/// Whether `actorRole` may remove/ban/demote a member with `targetRole` — you must strictly
/// outrank the target (mirrors the backend `can_moderate`; the owner is never a valid target).
bool canModerate(String? actorRole, String targetRole) {
  if (actorRole == null || targetRole == 'owner') return false;
  return roleRank(actorRole) > roleRank(targetRole);
}

/// Payload passed to the group chat route: the display name for the header plus the group id
/// (so the chat header can open the group detail/admin screen).
class GroupChatArgs {
  final String name;
  final String? groupId;
  const GroupChatArgs({required this.name, this.groupId});
}
