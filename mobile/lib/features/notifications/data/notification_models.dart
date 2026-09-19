/// In-app notification, mirroring the backend `/notifications` payload. Structured (type + group
/// + actor); the sentence is composed here so renamed groups/people always read correctly.
class AppNotification {
  final String id;
  final String type;
  final bool read;
  final DateTime createdAt;
  final String? groupId;
  final String? groupName;
  final String? actorId;
  final String? actorName;
  final String? actorAvatarUrl;

  /// What tapping this row should open, when the group and actor cannot say — e.g.
  /// `('attendance_session', <uuid>)`. See the `notifications` model server-side for why this is
  /// a generic pair rather than a column per notification type.
  ///
  /// An unrecognised [targetType] is treated as no target at all, so a type added server-side
  /// cannot break a client that predates it.
  final String? targetType;
  final String? targetId;

  /// A short display token belonging to this one event — currently the reaction emoji. The
  /// structured fields cannot carry it: [type] says what happened and [actorName] who, but which
  /// emoji is true of this row alone.
  final String? detail;

  const AppNotification({
    required this.id,
    required this.type,
    required this.read,
    required this.createdAt,
    this.groupId,
    this.groupName,
    this.actorId,
    this.actorName,
    this.actorAvatarUrl,
    this.targetType,
    this.targetId,
    this.detail,
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
      actorId: actor?['id'] as String?,
      actorName: actor?['display_name'] as String?,
      actorAvatarUrl: actor?['avatar_url'] as String?,
      targetType: j['target_type'] as String?,
      targetId: j['target_id'] as String?,
      detail: j['detail'] as String?,
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
        'honors_attendance_open' => 'Honors attendance is open — tap to scan the classroom QR',
        // The emoji when the server sent one, so the row says which reaction. Rows written before
        // `detail` existed fall back to the plain sentence rather than rendering "null".
        'message_reaction' => detail == null
            ? '$_actor reacted to your message'
            : '$_actor reacted $detail to your message',
        _ => 'You have a new notification',
      };

  /// Where tapping the notification navigates: the group for group events, the connections
  /// screen for connection events, the professional profile for scholar verification, or nowhere.
  String? get route {
    if (type.startsWith('connection_')) return '/connections';
    // Verification is only useful if it takes them to the thing it unlocked — the professional
    // extension they can now fill in.
    if (type == 'program_membership_verified') return '/profile/blueprint-bond';
    if (type == 'honors_attendance_open') {
      // Carrying the session id is the point (report #15). Without it the scanner had to work
      // out which session was meant from "whichever is currently active" — wrong the moment one
      // closes and another opens, and the user got "Attendance is closed" with no clue which
      // session that referred to. Falls back to the bare route for rows written before the
      // target existed.
      final session = targetId;
      return session == null ? '/attendance/scan' : '/attendance/scan?session=$session';
    }
    // The server says which chat route this is, so the client never has to infer
    // DM-vs-group from a thread list that may not be loaded yet — the bug
    // `openMessageConversation` had on a cold start.
    if (type == 'message_reaction' && targetId != null) {
      return targetType == 'group_chat' ? '/chat/group/$targetId' : '/chat/$targetId';
    }
    if (groupId != null) return '/groups/$groupId';
    return null;
  }

  /// True when the sentence is about what a *person* did ("Alex invited you…") — show their
  /// face. False for outcome-style events about you ("You're now a member…") — show a type icon.
  bool get isActorCentric =>
      actorName != null &&
      (type == 'group_invite' ||
          type == 'group_join_request' ||
          // A reaction is entirely about what a person did, so show their face.
          type == 'message_reaction' ||
          type.startsWith('connection_'));
}
