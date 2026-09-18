import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/connections/providers/connections_provider.dart';
import 'package:lc_connect/features/connections/screens/connections_screen.dart';

// ── Mock notifier helpers ─────────────────────────────────────────

class _MockConnectionsNotifier extends ConnectionsNotifier {
  final ConnectionsState _fixed;
  _MockConnectionsNotifier(this._fixed);

  @override
  Future<ConnectionsState> build() async => _fixed;
}

/// Never completes, so a test can inspect the screen mid-load.
class _PendingConnectionsNotifier extends ConnectionsNotifier {
  @override
  Future<ConnectionsState> build() => Completer<ConnectionsState>().future;
}

// Build a ProviderScope with ConnectionsState overridden
ProviderScope _scope({
  List<ConnectionRequest> incoming = const [],
  List<ConnectionRequest> outgoing = const [],
  Widget? child,
  bool pending = false,
}) {
  return ProviderScope(
    overrides: [
      connectionsNotifierProvider.overrideWith(
        () => pending
            ? _PendingConnectionsNotifier()
            : _MockConnectionsNotifier(
                ConnectionsState(incoming: incoming, outgoing: outgoing),
              ),
      ),
    ],
    child: MaterialApp(
      home: child ?? const ConnectionsScreen(),
    ),
  );
}

// ── Sample data ───────────────────────────────────────────────────
final _samplePartner = PartnerProfile(
  profileId: 'prof-001',
  userId: 'user-001',
  displayName: 'Maya Chen',
  major: 'Biology',
  classYear: 2027,
  lookingFor: ['Study Partner'],
);

final _sampleIncoming = ConnectionRequest(
  id: 'req-001',
  senderId: 'user-001',
  receiverId: 'user-me',
  intent: 'study_together',
  note: 'Let\'s study together!',
  status: 'pending',
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  partnerProfile: _samplePartner,
);

final _sampleOutgoing = ConnectionRequest(
  id: 'req-002',
  senderId: 'user-me',
  receiverId: 'user-002',
  intent: 'connect',
  note: null,
  status: 'pending',
  createdAt: DateTime.now().subtract(const Duration(days: 1)),
  partnerProfile: PartnerProfile(
    profileId: 'prof-002',
    userId: 'user-002',
    displayName: 'Ethan R.',
    major: 'Economics',
    classYear: 2026,
    lookingFor: ['Friendship'],
  ),
);

// ── Model unit tests ──────────────────────────────────────────────
void main() {
  group('ConnectionRequest.fromJson', () {
    test('parses full response with partner_profile', () {
      final json = {
        'id': 'abc-123',
        'sender_id': 'sender-id',
        'receiver_id': 'receiver-id',
        'intent': 'connect',
        'note': 'Hey!',
        'status': 'pending',
        'created_at': '2025-05-01T10:00:00.000Z',
        'partner_profile': {
          'id': 'prof-id',
          'user_id': 'user-id',
          'display_name': 'Alice',
          'avatar_url': null,
          'major': 'CS',
          'class_year': 2026,
          'pronouns': null,
          'country_state': null,
          'campus': null,
          'bio': null,
          'is_hidden': false,
          'profile_completed': true,
          'interests': ['Coding'],
          'languages_spoken': ['English'],
          'languages_learning': [],
          'looking_for': ['Study Partner'],
          'looking_for_codes': ['study_partner'],
        },
      };

      final req = ConnectionRequest.fromJson(json);

      expect(req.id, 'abc-123');
      expect(req.senderId, 'sender-id');
      expect(req.receiverId, 'receiver-id');
      expect(req.intent, 'connect');
      expect(req.note, 'Hey!');
      expect(req.status, 'pending');
      expect(req.partnerProfile, isNotNull);
      expect(req.partnerProfile!.displayName, 'Alice');
      expect(req.partnerProfile!.major, 'CS');
      expect(req.partnerProfile!.lookingFor, contains('Study Partner'));
    });

    test('parses response without partner_profile', () {
      final json = {
        'id': 'req-no-profile',
        'sender_id': 'a',
        'receiver_id': 'b',
        'intent': null,
        'note': null,
        'status': 'pending',
        'created_at': '2025-04-15T08:30:00.000Z',
        'partner_profile': null,
      };

      final req = ConnectionRequest.fromJson(json);

      expect(req.id, 'req-no-profile');
      expect(req.intent, isNull);
      expect(req.partnerProfile, isNull);
    });

    test('parses ISO timestamp correctly', () {
      final json = {
        'id': 'ts-test',
        'sender_id': 'a',
        'receiver_id': 'b',
        'intent': null,
        'note': null,
        'status': 'pending',
        'created_at': '2025-01-20T14:30:00.000Z',
        'partner_profile': null,
      };

      final req = ConnectionRequest.fromJson(json);
      expect(req.createdAt.year, 2025);
      expect(req.createdAt.month, 1);
      expect(req.createdAt.day, 20);
    });
  });

  group('PartnerProfile.fromJson', () {
    test('parses all fields', () {
      final json = {
        'id': 'prof-id',
        'user_id': 'user-id',
        'display_name': 'Sophia',
        'avatar_url': 'https://example.com/avatar.jpg',
        'major': 'Psychology',
        'class_year': 2028,
        'pronouns': null,
        'country_state': null,
        'campus': null,
        'bio': null,
        'is_hidden': false,
        'profile_completed': true,
        'interests': [],
        'languages_spoken': [],
        'languages_learning': [],
        'looking_for': ['Friendship', 'Study Partner'],
        'looking_for_codes': ['friendship', 'study_partner'],
      };

      final p = PartnerProfile.fromJson(json);
      expect(p.displayName, 'Sophia');
      expect(p.avatarUrl, 'https://example.com/avatar.jpg');
      expect(p.major, 'Psychology');
      expect(p.lookingFor.length, 2);
    });
  });

  // ── Widget tests ──────────────────────────────────────────────────
  group('ConnectionsScreen', () {
    testWidgets('shows empty state on incoming tab when no requests',
        (tester) async {
      await tester.pumpWidget(_scope());
      await tester.pumpAndSettle();

      expect(find.text('Incoming'), findsOneWidget);
      expect(find.text('No incoming requests'), findsOneWidget);
    });

    testWidgets('shows incoming request card with partner name',
        (tester) async {
      await tester.pumpWidget(_scope(incoming: [_sampleIncoming]));
      await tester.pumpAndSettle();

      expect(find.text('Maya Chen'), findsOneWidget);
      expect(find.text('Biology'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('shows intent badge on incoming card', (tester) async {
      await tester.pumpWidget(_scope(incoming: [_sampleIncoming]));
      await tester.pumpAndSettle();

      expect(find.text('Wants to Study Together'), findsOneWidget);
    });

    testWidgets('shows note on incoming card', (tester) async {
      await tester.pumpWidget(_scope(incoming: [_sampleIncoming]));
      await tester.pumpAndSettle();

      expect(find.textContaining('Let\'s study together!'), findsOneWidget);
    });

    testWidgets('shows outgoing tab with pending badge', (tester) async {
      await tester.pumpWidget(_scope(outgoing: [_sampleOutgoing]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Outgoing'));
      await tester.pumpAndSettle();

      expect(find.text('Ethan R.'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('shows empty outgoing state when no outgoing requests',
        (tester) async {
      await tester.pumpWidget(_scope());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Outgoing'));
      await tester.pumpAndSettle();

      expect(find.text('No pending requests'), findsOneWidget);
    });

    testWidgets('tab badge shows incoming count', (tester) async {
      await tester
          .pumpWidget(_scope(incoming: [_sampleIncoming, _sampleIncoming]));
      await tester.pumpAndSettle();

      // Badge with count 2 should appear on Incoming tab
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('incomingConnectionCountProvider', () {
    test('exposes incoming list length', () async {
      final container = ProviderContainer(
        overrides: [
          connectionsNotifierProvider.overrideWith(
            () => _MockConnectionsNotifier(
              ConnectionsState(
                incoming: [_sampleIncoming, _sampleIncoming],
                outgoing: const [],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(connectionsNotifierProvider.future);
      expect(container.read(incomingConnectionCountProvider), 2);
    });
  });

  /// Report #20 (4.5) — the tab bar used to render `SizedBox.shrink()` for both loading *and*
  /// error, so it appeared only once the request finished and shoved the list down. A layout
  /// jump on every visit, and on a slow connection one the user was already reading through.
  group('the tab bar does not pop in', () {
    testWidgets('it is present while loading', (tester) async {
      await tester.pumpWidget(_scope(pending: true));
      await tester.pump();

      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('Incoming'), findsOneWidget);
      expect(find.text('Outgoing'), findsOneWidget);
    });

    testWidgets('it does not move once the counts arrive', (tester) async {
      // The actual regression: same position before and after. The counts are what load; the
      // tabs themselves are known from the start.
      await tester.pumpWidget(_scope(pending: true));
      await tester.pump();
      final whileLoading = tester.getTopLeft(find.byType(TabBar));

      // Explicit pumps, not `pumpAndSettle`: a skeleton is on screen during the loading frame
      // and it shimmers, so there is no idle state to settle to.
      await tester.pumpWidget(_scope(incoming: [_sampleIncoming]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final afterLoad = tester.getTopLeft(find.byType(TabBar));

      expect(afterLoad, whileLoading);
    });

    testWidgets('it shows no count badges while loading', (tester) async {
      // Present but honest: a zero or a stale number would be worse than no badge.
      await tester.pumpWidget(_scope(pending: true));
      await tester.pump();

      expect(find.text('0'), findsNothing);
    });
  });
}
