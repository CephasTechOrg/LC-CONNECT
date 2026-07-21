import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../../messages/providers/messages_provider.dart';

// ── Partner profile (subset of ProfilePublic) ────────────────────
class PartnerProfile {
  final String profileId;
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final String? major;
  final int? classYear;
  final List<String> lookingFor;

  const PartnerProfile({
    required this.profileId,
    required this.userId,
    this.displayName,
    this.avatarUrl,
    this.major,
    this.classYear,
    required this.lookingFor,
  });

  factory PartnerProfile.fromJson(Map<String, dynamic> j) => PartnerProfile(
        profileId: j['id'] as String,
        userId: j['user_id'] as String,
        displayName: j['display_name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        major: j['major'] as String?,
        classYear: j['class_year'] as int?,
        lookingFor: List<String>.from(j['looking_for'] ?? []),
      );
}

// ── Connection request ────────────────────────────────────────────
class ConnectionRequest {
  final String id;
  final String senderId;
  final String receiverId;
  final String? intent;
  final String? note;
  final String status;
  final DateTime createdAt;
  final PartnerProfile? partnerProfile;

  const ConnectionRequest({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.intent,
    this.note,
    required this.status,
    required this.createdAt,
    this.partnerProfile,
  });

  factory ConnectionRequest.fromJson(Map<String, dynamic> j) =>
      ConnectionRequest(
        id: j['id'] as String,
        senderId: j['sender_id'] as String,
        receiverId: j['receiver_id'] as String,
        intent: j['intent'] as String?,
        note: j['note'] as String?,
        status: j['status'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        partnerProfile: j['partner_profile'] != null
            ? PartnerProfile.fromJson(
                j['partner_profile'] as Map<String, dynamic>)
            : null,
      );
}

// ── State held by the notifier ────────────────────────────────────
class ConnectionsState {
  final List<ConnectionRequest> incoming;
  final List<ConnectionRequest> outgoing;

  const ConnectionsState({
    required this.incoming,
    required this.outgoing,
  });

  ConnectionsState copyWith({
    List<ConnectionRequest>? incoming,
    List<ConnectionRequest>? outgoing,
  }) =>
      ConnectionsState(
        incoming: incoming ?? this.incoming,
        outgoing: outgoing ?? this.outgoing,
      );
}

// ── Provider ──────────────────────────────────────────────────────
final connectionsNotifierProvider =
    AsyncNotifierProvider<ConnectionsNotifier, ConnectionsState>(
        ConnectionsNotifier.new);

class ConnectionsNotifier extends AsyncNotifier<ConnectionsState> {
  @override
  Future<ConnectionsState> build() async {
    ref.watch(authNotifierProvider);
    final client = ref.watch(apiClientProvider);
    final results = await Future.wait([
      client.dio.get('/connections/incoming'),
      client.dio.get('/connections/outgoing'),
    ]);

    return ConnectionsState(
      incoming: (results[0].data as List)
          .map((j) => ConnectionRequest.fromJson(j as Map<String, dynamic>))
          .toList(),
      outgoing: (results[1].data as List)
          .map((j) => ConnectionRequest.fromJson(j as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> accept(String requestId) async {
    final client = ref.read(apiClientProvider);
    await client.dio.post('/connections/$requestId/accept');
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      incoming: current.incoming.where((r) => r.id != requestId).toList(),
    ));
    // New match created — refresh threads so Messages tab shows it immediately
    ref.invalidate(threadsNotifierProvider);
  }

  Future<void> decline(String requestId) async {
    final client = ref.read(apiClientProvider);
    await client.dio.post('/connections/$requestId/decline');
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      incoming: current.incoming.where((r) => r.id != requestId).toList(),
    ));
  }
}
