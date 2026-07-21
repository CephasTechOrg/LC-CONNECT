import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/profile/providers/profile_provider.dart';
import 'package:lc_connect/features/profile/screens/profile_screen.dart';

// ── Mock notifiers ────────────────────────────────────────────────
class _MockProfileNotifier extends MyProfileNotifier {
  final MyProfile _fixed;
  _MockProfileNotifier(this._fixed);

  @override
  Future<MyProfile> build() async => _fixed;
}

class _MockAuthNotifier extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => AuthUser(
        id: 'user-me',
        email: 'me@livingstone.edu',
        role: 'student',
        profileCompleted: true,
      );
}

ProviderScope _scope(MyProfile profile) {
  return ProviderScope(
    overrides: [
      myProfileNotifierProvider
          .overrideWith(() => _MockProfileNotifier(profile)),
      authNotifierProvider.overrideWith(_MockAuthNotifier.new),
    ],
    child: const MaterialApp(home: ProfileScreen()),
  );
}

// ── Sample profiles ───────────────────────────────────────────────
MyProfile _makeProfile({
  String? displayName = 'Maya Chen',
  String? bio = 'Always up for meaningful conversations.',
  String? major = 'Psychology',
  int? classYear = 2027,
  String? campus = 'Livingstone Campus',
  List<String> interests = const ['Photography', 'Hiking'],
  List<String> languagesSpoken = const ['English', 'Mandarin'],
  List<String> languagesLearning = const ['French'],
  List<String> lookingFor = const ['Friendship', 'Study Partner'],
  List<String> lookingForCodes = const ['friendship', 'study_partner'],
  bool allowMessages = true,
  bool showToVerified = true,
  bool isVerified = true,
  int connections = 42,
  int activities = 7,
  int messages = 15,
}) =>
    MyProfile(
      profileId: 'prof-001',
      userId: 'user-001',
      displayName: displayName,
      bio: bio,
      major: major,
      classYear: classYear,
      campus: campus,
      interests: interests,
      languagesSpoken: languagesSpoken,
      languagesLearning: languagesLearning,
      lookingFor: lookingFor,
      lookingForCodes: lookingForCodes,
      allowMessagesFromMatchesOnly: allowMessages,
      showProfileToVerifiedOnly: showToVerified,
      isVerified: isVerified,
      connectionCount: connections,
      activityCount: activities,
      messageCount: messages,
      isHidden: false,
      profileCompleted: true,
    );

// ── Model unit tests ──────────────────────────────────────────────
void main() {
  group('MyProfile.fromJson', () {
    final fullJson = {
      'id': 'prof-001',
      'user_id': 'user-001',
      'display_name': 'Maya Chen',
      'pronouns': 'she/her',
      'major': 'Psychology',
      'class_year': 2027,
      'country_state': null,
      'campus': 'Livingstone Campus',
      'bio': 'Hello!',
      'avatar_url': null,
      'is_hidden': false,
      'is_verified': true,
      'profile_completed': true,
      'interests': ['Photography', 'Hiking'],
      'languages_spoken': ['English', 'Mandarin'],
      'languages_learning': ['French'],
      'looking_for': ['Friendship', 'Study Partner'],
      'looking_for_codes': ['friendship', 'study_partner'],
      'allow_messages_from_matches_only': true,
      'show_profile_to_verified_only': false,
      'connection_count': 42,
      'activity_count': 7,
      'message_count': 15,
    };

    test('parses all scalar fields', () {
      final p = MyProfile.fromJson(fullJson);
      expect(p.profileId, 'prof-001');
      expect(p.displayName, 'Maya Chen');
      expect(p.pronouns, 'she/her');
      expect(p.major, 'Psychology');
      expect(p.classYear, 2027);
      expect(p.campus, 'Livingstone Campus');
      expect(p.bio, 'Hello!');
    });

    test('parses list fields', () {
      final p = MyProfile.fromJson(fullJson);
      expect(p.interests, containsAll(['Photography', 'Hiking']));
      expect(p.languagesSpoken, containsAll(['English', 'Mandarin']));
      expect(p.languagesLearning, contains('French'));
      expect(p.lookingFor, containsAll(['Friendship', 'Study Partner']));
      expect(p.lookingForCodes, contains('study_partner'));
    });

    test('parses is_verified field', () {
      final p = MyProfile.fromJson(fullJson);
      expect(p.isVerified, isTrue);
    });

    test('defaults is_verified to false when absent', () {
      final json = Map<String, dynamic>.from(fullJson)
        ..remove('is_verified');
      final p = MyProfile.fromJson(json);
      expect(p.isVerified, isFalse);
    });

    test('parses preference booleans', () {
      final p = MyProfile.fromJson(fullJson);
      expect(p.allowMessagesFromMatchesOnly, isTrue);
      expect(p.showProfileToVerifiedOnly, isFalse);
    });

    test('parses stat counts', () {
      final p = MyProfile.fromJson(fullJson);
      expect(p.connectionCount, 42);
      expect(p.activityCount, 7);
      expect(p.messageCount, 15);
    });

    test('defaults missing fields to safe values', () {
      final minimal = {
        'id': 'prof-min',
        'user_id': 'user-min',
        'display_name': null,
        'pronouns': null,
        'major': null,
        'class_year': null,
        'country_state': null,
        'campus': null,
        'bio': null,
        'avatar_url': null,
        'is_hidden': false,
        'profile_completed': false,
        'interests': null,
        'languages_spoken': null,
        'languages_learning': null,
        'looking_for': null,
        'looking_for_codes': null,
        'allow_messages_from_matches_only': null,
        'show_profile_to_verified_only': null,
        'connection_count': null,
        'activity_count': null,
        'message_count': null,
      };
      final p = MyProfile.fromJson(minimal);
      expect(p.interests, isEmpty);
      expect(p.connectionCount, 0);
      expect(p.allowMessagesFromMatchesOnly, isTrue);
    });

    test('copyWith updates only specified fields', () {
      final p = MyProfile.fromJson(fullJson);
      final updated = p.copyWith(allowMessagesFromMatchesOnly: false);
      expect(updated.allowMessagesFromMatchesOnly, isFalse);
      expect(updated.showProfileToVerifiedOnly, isFalse);
      expect(updated.displayName, 'Maya Chen');
      expect(updated.connectionCount, 42);
    });
  });

  // ── Widget tests ──────────────────────────────────────────────────
  group('ProfileScreen', () {
    testWidgets('shows display name in hero', (tester) async {
      await tester.pumpWidget(_scope(_makeProfile()));
      await tester.pumpAndSettle();
      expect(find.text('Maya Chen'), findsOneWidget);
    });

    testWidgets('shows bio text', (tester) async {
      await tester.pumpWidget(_scope(_makeProfile()));
      await tester.pumpAndSettle();
      expect(find.text('Always up for meaningful conversations.'),
          findsOneWidget);
    });

    testWidgets('shows major and class year', (tester) async {
      await tester.pumpWidget(_scope(_makeProfile()));
      await tester.pumpAndSettle();
      expect(find.text('Psychology'), findsOneWidget);
      expect(find.text('Class of 2027'), findsOneWidget);
    });

    testWidgets('shows campus/location', (tester) async {
      await tester.pumpWidget(_scope(_makeProfile()));
      await tester.pumpAndSettle();
      expect(find.text('Livingstone Campus'), findsOneWidget);
    });

    testWidgets('shows languages spoken', (tester) async {
      await tester.pumpWidget(_scope(_makeProfile()));
      await tester.pumpAndSettle();
      expect(find.text('English, Mandarin'), findsOneWidget);
    });

    testWidgets('shows languages learning', (tester) async {
      await tester.pumpWidget(_scope(_makeProfile()));
      await tester.pumpAndSettle();
      expect(find.text('French'), findsOneWidget);
    });

    testWidgets('shows interests', (tester) async {
      await tester.pumpWidget(_scope(_makeProfile()));
      await tester.pumpAndSettle();
      expect(find.text('Photography, Hiking'), findsOneWidget);
    });

    testWidgets('shows looking for chips', (tester) async {
      await tester.pumpWidget(_scope(_makeProfile()));
      await tester.pumpAndSettle();
      expect(find.text('Friendship'), findsOneWidget);
      expect(find.text('Study Partner'), findsOneWidget);
    });

    testWidgets('shows stats row', (tester) async {
      await tester.pumpWidget(_scope(_makeProfile()));
      await tester.pumpAndSettle();
      // Stats are below the fold — search off-stage elements too
      expect(find.text('42', skipOffstage: false), findsOneWidget);
      expect(find.text('7', skipOffstage: false), findsOneWidget);
      expect(find.text('15', skipOffstage: false), findsOneWidget);
      expect(find.text('Connections', skipOffstage: false), findsOneWidget);
      expect(find.text('Joined Activities', skipOffstage: false),
          findsOneWidget);
      expect(find.text('Messages', skipOffstage: false), findsOneWidget);
    });

    testWidgets('shows preference toggles', (tester) async {
      await tester.pumpWidget(_scope(_makeProfile()));
      await tester.pumpAndSettle();
      expect(
          find.text('Preferences', skipOffstage: false), findsOneWidget);
      expect(find.byType(Switch, skipOffstage: false), findsNWidgets(2));
    });

    testWidgets('shows Edit Profile button', (tester) async {
      await tester.pumpWidget(_scope(_makeProfile()));
      await tester.pumpAndSettle();
      // Scroll to bring the button into the build cache
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Edit Profile'), findsOneWidget);
    });

    testWidgets('shows verified badge and row when isVerified is true',
        (tester) async {
      await tester.pumpWidget(_scope(_makeProfile(isVerified: true)));
      await tester.pumpAndSettle();
      expect(find.text('Verified Student'), findsOneWidget);
      expect(
        find.byIcon(Icons.verified_rounded, skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('hides verified badge and row when isVerified is false',
        (tester) async {
      await tester.pumpWidget(_scope(_makeProfile(isVerified: false)));
      await tester.pumpAndSettle();
      expect(find.text('Verified Student', skipOffstage: false), findsNothing);
      expect(
        find.byIcon(Icons.verified_rounded, skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('handles empty optional fields gracefully', (tester) async {
      final sparse = _makeProfile(
        bio: null,
        campus: null,
        interests: [],
        languagesSpoken: [],
        languagesLearning: [],
      );
      await tester.pumpWidget(_scope(sparse));
      await tester.pumpAndSettle();
      // Should render without crash
      expect(find.text('Maya Chen'), findsOneWidget);
    });
  });
}
