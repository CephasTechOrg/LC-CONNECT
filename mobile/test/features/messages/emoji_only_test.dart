import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/messages/data/emoji_only.dart';

void main() {
  test('one to three emoji count as emoji-only', () {
    expect(isEmojiOnly('🫡'), isTrue);
    expect(isEmojiOnly('👍🏽'), isTrue);
    expect(isEmojiOnly('❤️ 😂 🔥'), isTrue);
    expect(isEmojiOnly('🇺🇸'), isTrue);
  });

  test('text, digits, or too many emoji are not', () {
    expect(isEmojiOnly('ok 👍'), isFalse);
    expect(isEmojiOnly('123'), isFalse);
    expect(isEmojiOnly('#'), isFalse);
    expect(isEmojiOnly('😂😂😂😂'), isFalse);
    expect(isEmojiOnly('   '), isFalse);
    expect(isEmojiOnly(''), isFalse);
  });
}
