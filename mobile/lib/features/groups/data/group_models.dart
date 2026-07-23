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

  /// The join button label given the group's policy + my membership state.
  String get actionLabel {
    if (isMember) return 'Joined';
    if (isPending) return 'Pending';
    if (myStatus == 'invited') return 'Accept';
    return switch (joinPolicy) {
      'approval' => 'Request',
      'invite' => 'Invite only',
      _ => 'Join',
    };
  }

  bool get actionEnabled => !isMember && !isPending && joinPolicy != 'invite';

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
}
