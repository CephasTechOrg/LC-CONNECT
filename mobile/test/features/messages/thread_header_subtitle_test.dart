import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';

/// The chat header said only a name for students, while the inbox row under it showed their
/// major. It now says who you are talking to in both places.
MessageThread _thread({String? major, int? year, String? position, String? department}) => MessageThread(
      conversationId: 'c1',
      kind: 'dm',
      matchId: 'c1',
      partnerPositionTitle: position,
      partnerDepartment: department,
      partner: MessagePartner(
        profileId: 'p1',
        userId: 'u1',
        displayName: 'Kwame Asante',
        major: major,
        classYear: year,
        interests: const [],
        lookingFor: const [],
        languagesSpoken: const [],
        languagesLearning: const [],
      ),
    );

void main() {
  test('a student reads as major and class year', () {
    expect(_thread(major: 'Computer Science', year: 2027).headerSubtitle,
        'Computer Science · Class of 2027');
  });

  test('staff keep their position', () {
    expect(
      _thread(major: 'Ignored', position: 'Academic Advisor', department: 'Advising Center').headerSubtitle,
      'Academic Advisor · Advising Center',
    );
  });

  test('nothing to say means no line', () {
    expect(_thread().headerSubtitle, isNull);
  });
}
