import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/campus_hub/data/greeting_name.dart';

/// The greeting names the user on its first frame (from bootstrap) and prefers the loaded profile
/// once it arrives, so a rename made in this session shows at once.
void main() {
  group('resolveGreetingName', () {
    test('names the user from bootstrap before the profile has loaded', () {
      expect(
        resolveGreetingName(accountDisplayName: 'Kwame Osei', firstName: 'Cephas'),
        'Kwame',
      );
    });

    test('prefers the loaded profile name, which reflects a rename', () {
      expect(
        resolveGreetingName(profileDisplayName: 'Ama Mensah', accountDisplayName: 'Kwame Osei'),
        'Ama',
      );
    });

    test('falls back to the signup first name when there is no display name', () {
      expect(
        resolveGreetingName(profileDisplayName: '  ', firstName: 'Cephas', email: 'c@x.edu'),
        'Cephas',
      );
    });

    test('uses the capitalized email local part only when no name exists', () {
      expect(resolveGreetingName(email: 'ama.boateng@students.livingstone.edu'), 'Ama.boateng');
    });

    test('falls back to "there" when nothing is available', () {
      expect(resolveGreetingName(), 'there');
      expect(resolveGreetingName(email: ''), 'there');
    });
  });
}
