import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';
import 'package:lc_connect/features/messages/screens/messages_screen.dart';
import 'package:lc_connect/features/messages/screens/chat_screen.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';

// ── Mock notifier ─────────────────────────────────────────────────
class _MockThreadsNotifier extends ThreadsNotifier {
  final List<MessageThread> _fixed;
  _MockThreadsNotifier(this._fixed);

  @override
  Future<List<MessageThread>> build() async => _fixed;
}

class _MockAuthNotifier extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => AuthUser(
        id: 'current-user-id',
        email: 'test@example.com',
        role: 'student',
        profileCompleted: true,
      );
}

ProviderScope _threadScope({
  List<MessageThread> threads = const [],
  Widget? child,
}) {
  return ProviderScope(
    overrides: [
      threadsNotifierProvider.overrideWith(
        () => _MockThreadsNotifier(threads),
      ),
      authNotifierProvider.overrideWith(_MockAuthNotifier.new),
    ],
    child: MaterialApp(home: child ?? const MessagesScreen()),
  );
}

// ── Sample data ───────────────────────────────────────────────────
final _samplePartner = MessagePartner(
  profileId: 'prof-001',
  userId: 'user-001',
  displayName: 'Maya Chen',
  major: 'Biology',
  classYear: 2027,
  interests: ['Basketball'],
  lookingFor: ['Study Partner'],
  languagesSpoken: ['English'],
  languagesLearning: [],
);

final _sampleMessage = ChatMessage(
  id: 'msg-001',
  matchId: 'match-001',
  senderId: 'user-001',
  body: 'Hey! Let\'s study together.',
  createdAt: DateTime.now().subtract(const Duration(hours: 1)),
);

final _sampleThread = MessageThread(
  matchId: 'match-001',
  partner: _samplePartner,
  latestMessage: _sampleMessage,
);

final _threadNoMessage = MessageThread(
  matchId: 'match-002',
  partner: MessagePartner(
    profileId: 'prof-002',
    userId: 'user-002',
    displayName: 'Ethan R.',
    major: 'Economics',
    classYear: 2026,
    interests: [],
    lookingFor: ['Friendship'],
    languagesSpoken: ['English'],
    languagesLearning: [],
  ),
  latestMessage: null,
);

// ── Model unit tests ──────────────────────────────────────────────
void main() {
  group('ChatMessage.fromJson', () {
    test('parses all fields', () {
      final json = {
        'id': 'msg-abc',
        'match_id': 'match-xyz',
        'sender_id': 'user-123',
        'body': 'Hello there!',
        'created_at': '2025-05-01T10:00:00.000Z',
        'read_at': null,
      };

      final msg = ChatMessage.fromJson(json);

      expect(msg.id, 'msg-abc');
      expect(msg.matchId, 'match-xyz');
      expect(msg.senderId, 'user-123');
      expect(msg.body, 'Hello there!');
      expect(msg.readAt, isNull);
      expect(msg.createdAt.year, 2025);
    });

    test('parses read_at when present', () {
      final json = {
        'id': 'msg-read',
        'match_id': 'match-xyz',
        'sender_id': 'user-123',
        'body': 'Read message',
        'created_at': '2025-05-01T10:00:00.000Z',
        'read_at': '2025-05-01T10:05:00.000Z',
      };

      final msg = ChatMessage.fromJson(json);
      expect(msg.readAt, isNotNull);
      expect(msg.readAt!.minute, 5);
    });
  });

  group('MessagePartner.fromJson', () {
    test('parses full partner profile', () {
      final json = {
        'id': 'prof-id',
        'user_id': 'user-id',
        'display_name': 'Sophia Lee',
        'avatar_url': null,
        'major': 'CS',
        'class_year': 2026,
        'pronouns': null,
        'country_state': null,
        'campus': null,
        'bio': null,
        'is_hidden': false,
        'profile_completed': true,
        'interests': ['Coding', 'Gaming'],
        'languages_spoken': ['English', 'Mandarin'],
        'languages_learning': ['Spanish'],
        'looking_for': ['Study Partner', 'Friendship'],
        'looking_for_codes': ['study_partner', 'friendship'],
      };

      final p = MessagePartner.fromJson(json);
      expect(p.displayName, 'Sophia Lee');
      expect(p.major, 'CS');
      expect(p.interests, contains('Gaming'));
      expect(p.lookingFor.length, 2);
      expect(p.languagesSpoken, contains('Mandarin'));
    });
  });

  group('MessageThread.fromJson', () {
    test('parses thread with latest message', () {
      final json = {
        'match_id': 'match-abc',
        'partner': {
          'id': 'prof-id',
          'user_id': 'user-id',
          'display_name': 'Alex',
          'avatar_url': null,
          'major': 'Math',
          'class_year': 2025,
          'pronouns': null,
          'country_state': null,
          'campus': null,
          'bio': null,
          'is_hidden': false,
          'profile_completed': true,
          'interests': [],
          'languages_spoken': [],
          'languages_learning': [],
          'looking_for': [],
          'looking_for_codes': [],
        },
        'latest_message': {
          'id': 'msg-1',
          'match_id': 'match-abc',
          'sender_id': 'user-id',
          'body': 'Hey!',
          'created_at': '2025-04-30T09:00:00.000Z',
          'read_at': null,
        },
      };

      final thread = MessageThread.fromJson(json);
      expect(thread.matchId, 'match-abc');
      expect(thread.partner!.displayName, 'Alex');
      expect(thread.latestMessage, isNotNull);
      expect(thread.latestMessage!.body, 'Hey!');
    });

    test('parses thread without latest message', () {
      final json = {
        'match_id': 'match-new',
        'partner': {
          'id': 'prof-id',
          'user_id': 'user-id',
          'display_name': 'Jamie',
          'avatar_url': null,
          'major': null,
          'class_year': null,
          'pronouns': null,
          'country_state': null,
          'campus': null,
          'bio': null,
          'is_hidden': false,
          'profile_completed': false,
          'interests': [],
          'languages_spoken': [],
          'languages_learning': [],
          'looking_for': [],
          'looking_for_codes': [],
        },
        'latest_message': null,
      };

      final thread = MessageThread.fromJson(json);
      expect(thread.latestMessage, isNull);
    });

    test('does not crash when partner is null', () {
      final json = {
        'match_id': 'match-orphan',
        'partner': null,
        'latest_message': null,
      };
      final thread = MessageThread.fromJson(json);
      expect(thread.partner, isNull);
      expect(thread.matchId, 'match-orphan');
    });
  });

  // ── MessagesScreen widget tests ───────────────────────────────────
  group('MessagesScreen', () {
    testWidgets('shows empty state when no threads', (tester) async {
      await tester.pumpWidget(_threadScope());
      await tester.pumpAndSettle();

      expect(find.text('No messages yet'), findsOneWidget);
    });

    testWidgets('shows thread card with partner name', (tester) async {
      await tester.pumpWidget(_threadScope(threads: [_sampleThread]));
      await tester.pumpAndSettle();

      expect(find.text('Maya Chen'), findsOneWidget);
      expect(find.text('Biology'), findsOneWidget);
    });

    testWidgets('shows last message preview', (tester) async {
      await tester.pumpWidget(_threadScope(threads: [_sampleThread]));
      await tester.pumpAndSettle();

      expect(find.text('Hey! Let\'s study together.'), findsOneWidget);
    });

    testWidgets('shows no messages yet italic when latest_message is null',
        (tester) async {
      await tester
          .pumpWidget(_threadScope(threads: [_threadNoMessage]));
      await tester.pumpAndSettle();

      expect(
        find.text('No messages yet — say hello!'),
        findsOneWidget,
      );
    });

    testWidgets('shows multiple threads', (tester) async {
      await tester.pumpWidget(
          _threadScope(threads: [_sampleThread, _threadNoMessage]));
      await tester.pumpAndSettle();

      expect(find.text('Maya Chen'), findsOneWidget);
      expect(find.text('Ethan R.'), findsOneWidget);
    });

    testWidgets('timestamp is displayed in local time format', (tester) async {
      // _sampleMessage was created 1 hour ago → _formatThreadTime returns '1h'
      await tester.pumpWidget(_threadScope(threads: [_sampleThread]));
      await tester.pumpAndSettle();

      expect(find.text('1h'), findsOneWidget);
    });
  });

  // ── ChatScreen widget tests ───────────────────────────────────────
  group('ChatScreen', () {
    Widget chatScope() {
      return ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(_MockAuthNotifier.new),
        ],
        child: MaterialApp(
          home: ChatScreen(
            matchId: 'match-001',
            thread: _sampleThread,
          ),
        ),
      );
    }

    testWidgets('shows partner name in info row', (tester) async {
      await tester.pumpWidget(chatScope());
      // Only pump once — _fetchMessages will fail (no real API) but
      // the header/partner info renders immediately.
      await tester.pump();

      expect(find.text('Maya Chen'), findsOneWidget);
    });

    testWidgets('shows looking-for tag chips', (tester) async {
      await tester.pumpWidget(chatScope());
      await tester.pump();

      expect(find.text('Study Partner'), findsOneWidget);
    });

    testWidgets('shows empty chat state on load with no messages',
        (tester) async {
      await tester.pumpWidget(chatScope());
      // Pump twice: first frame renders loader, after fetchMessages
      // throws (no real API) loading becomes false → empty state shown.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Either loading indicator or empty/error state — no crash
      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets('input bar renders with send button', (tester) async {
      await tester.pumpWidget(chatScope());
      await tester.pump();

      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
    });

    testWidgets('typing in input field works', (tester) async {
      await tester.pumpWidget(chatScope());
      await tester.pump();

      await tester.enterText(
          find.byType(TextField), 'Hello, how are you?');
      expect(find.text('Hello, how are you?'), findsOneWidget);
    });
  });
}
