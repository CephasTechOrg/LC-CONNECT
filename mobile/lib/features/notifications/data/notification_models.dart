/// In-app notification, mirroring the backend `/notifications` payload. Structured (type + group
/// + actor); the sentence is composed here so renamed groups/people always read correctly.
class AppNotification {
  final String id;
  final String type;
  final bool read;
  final DateTime createdAt;
  final String? groupId;
  final String? groupName;
  final String? actorName;
  final String? actorAvatarUrl;

  const AppNotification({
    required this.id,
    required this.type,
    required this.read,
    required this.createdAt,
    this.groupId,
    this.groupName,
    this.actorName,
    this.actorAvatarUrl,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    final group = j['group'] as Map<String, dynamic>?;
    final actor = j['actor'] as Map<String, dynamic>?;
    return AppNotification(
      id: j['id'] as String,
      type: j['type'] as String,
      read: j['read'] as bool? ?? false,
      createdAt: DateTime.parse(j['created_at'] as String),
      groupId: group?['id'] as String?,
      groupName: group?['name'] as String?,
      actorName: actor?['display_name'] as String?,
      actorAvatarUrl: actor?['avatar_url'] as String?,
    );
  }

  String get _group => groupName ?? 'a group';
  String get _actor => actorName ?? 'Someone';

  /// The human sentence shown in the notification row.
  String get message => switch (type) {
        'group_invite' => '$_actor invited you to $_group',
        'group_request_approved' => "You're now a member of $_group",
        'group_request_rejected' => 'Your request to join $_group was declined',
        'group_made_admin' => "You're now an admin of $_group",
        'group_removed_admin' => "You're no longer an admin of $_group",
        'group_removed' => 'You were removed from $_group',
        'group_join_request' => '$_actor requested to join $_group',
        'connection_request' => '$_actor sent you a connection request',
        'connection_accepted' => '$_actor accepted your connection request',
        'admin_membership_invited' => "You've been granted admin access — sign in to the Admin Portal",
        'program_membership_verified' =>
          "You're a verified Presidential Scholar — complete your professional profile",
        _ => 'You have a new notification',
      };

  /// Where tapping the notification navigates: the group for group events, the connections
  /// screen for connection events, the professional profile for scholar verification, or nowhere.
  String? get route {
    if (type.startsWith('connection_')) return '/connections';
    // Verification is only useful if it takes them to the thing it unlocked — the professional
    // extension they can now fill in.
    if (type == 'program_membership_verified') return '/profile/blueprint-bond';
    if (groupId != null) return '/groups/$groupId';
    return null;
  }

  /// True when the sentence is about what a *person* did ("Alex invited you…") — show their
  /// face. False for outcome-style events about you ("You're now a member…") — show a type icon.
  bool get isActorCentric =>
      actorName != null &&
      (type == 'group_invite' || type == 'group_join_request' || type.startsWith('connection_'));
}
