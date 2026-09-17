import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';
import 'package:lc_connect/features/messages/widgets/message_status_icon.dart';

/// Reports #21 (a delivered state existed nowhere) and #23 (the tick was too weak to read).
void main() {
  final createdAt = DateTime.utc(2026, 1, 1, 16, 12);

  ChatMessage mine({
    MessageStatus status = MessageStatus.sent,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) =>
      ChatMessage(
        id: 'srv-1',
        matchId: 'match-1',
        senderId: 'me',
        body: 'hello',
        createdAt: createdAt,
        status: status,
        deliveredAt: deliveredAt,
        readAt: readAt,
      );

  group('OutgoingState', () {
    test('an in-flight message is sending', () {
      expect(OutgoingState.of(mine(status: MessageStatus.sending)), OutgoingState.sending);
    });

    test('a message the server has is sent', () {
      expect(OutgoingState.of(mine()), OutgoingState.sent);
    });

    test('an acknowledged message is delivered', () {
      expect(OutgoingState.of(mine(deliveredAt: createdAt)), OutgoingState.delivered);
    });

    test('read outranks delivered', () {
      // Both timestamps are set for a read message; showing "delivered" would understate it.
      expect(
        OutgoingState.of(mine(deliveredAt: createdAt, readAt: createdAt)),
        OutgoingState.read,
      );
    });

    test('a read message with no delivery timestamp still reads as read', () {
      // A protocol 1 server sends no delivery timestamp at all. Read must not depend on one.
      expect(OutgoingState.of(mine(readAt: createdAt)), OutgoingState.read);
    });

    test('failure outranks delivery', () {
      // A retry can fail after the original was delivered. The sender needs to see the failure —
      // it is the only state with an action attached.
      expect(
        OutgoingState.of(mine(status: MessageStatus.failed, deliveredAt: createdAt)),
        OutgoingState.failed,
      );
    });

    test('a message with no delivery information is sent, never delivered', () {
      // The direction of the guess matters: understating progress is a missing tick, overstating
      // it is a false claim about another person.
      expect(OutgoingState.of(mine()), isNot(OutgoingState.delivered));
    });
  });

  group('rendering', () {
    Future<void> pump(WidgetTester tester, ChatMessage message, {bool compact = false}) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(body: MessageStatusIcon(message: message, compact: compact)),
        ));

    testWidgets('sending shows a clock', (tester) async {
      await pump(tester, mine(status: MessageStatus.sending));
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    });

    testWidgets('sent shows one tick', (tester) async {
      await pump(tester, mine());
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.done_all_rounded), findsNothing);
    });

    testWidgets('delivered shows two ticks', (tester) async {
      await pump(tester, mine(deliveredAt: createdAt));
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
    });

    testWidgets('delivered and read differ by colour, not by glyph', (tester) async {
      // Both are `done_all`, so colour is the only distinction — which is precisely why the
      // semantics label below is not optional.
      await pump(tester, mine(deliveredAt: createdAt));
      final delivered = tester.widget<Icon>(find.byIcon(Icons.done_all_rounded)).color;

      await pump(tester, mine(deliveredAt: createdAt, readAt: createdAt));
      final read = tester.widget<Icon>(find.byIcon(Icons.done_all_rounded)).color;

      expect(delivered, isNot(read));
    });

    testWidgets('every state is at least 14px', (tester) async {
      // Report #23: at 12px, one tick and two small ticks were genuinely hard to tell apart, and
      // delivery adds a third state to the same glyph pair.
      for (final message in [
        mine(status: MessageStatus.sending),
        mine(),
        mine(deliveredAt: createdAt),
        mine(deliveredAt: createdAt, readAt: createdAt),
      ]) {
        await pump(tester, message);
        expect(tester.widget<Icon>(find.byType(Icon)).size, greaterThanOrEqualTo(14));
      }
    });

    testWidgets('a failure offers Retry when there is a handler', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageStatusIcon(message: mine(status: MessageStatus.failed), onRetry: (_) {}),
        ),
      ));
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a failure with no handler shows no Retry label', (tester) async {
      // The previous implementation rendered the label unconditionally and called
      // `onRetry?.call` — so a caller that passed no handler got a "Retry" that did nothing.
      await pump(tester, mine(status: MessageStatus.failed));
      expect(find.text('Retry'), findsNothing);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('compact drops the Retry label', (tester) async {
      // The conversation row has no room for it, and retrying belongs in the conversation.
      await pump(tester, mine(status: MessageStatus.failed), compact: true);
      expect(find.text('Retry'), findsNothing);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('tapping Retry reports the message', (tester) async {
      ChatMessage? retried;
      final message = mine(status: MessageStatus.failed);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageStatusIcon(message: message, onRetry: (m) => retried = m),
        ),
      ));

      await tester.tap(find.text('Retry'));
      expect(retried, same(message));
    });
  });

  group('accessibility', () {
    test('each state has a distinct spoken label', () {
      // Icon shape and colour are both invisible to a screen reader, so without these four
      // states are indistinguishable.
      final labels = {
        MessageStatusIcon.semanticsLabelFor(mine(status: MessageStatus.sending)),
        MessageStatusIcon.semanticsLabelFor(mine()),
        MessageStatusIcon.semanticsLabelFor(mine(deliveredAt: createdAt)),
        MessageStatusIcon.semanticsLabelFor(mine(deliveredAt: createdAt, readAt: createdAt)),
        MessageStatusIcon.semanticsLabelFor(mine(status: MessageStatus.failed)),
      };
      expect(labels, hasLength(5));
    });

    test('read and delivered labels carry the time', () {
      // "Read" alone answers a different question from the one a sender is asking.
      expect(
        MessageStatusIcon.semanticsLabelFor(mine(deliveredAt: createdAt, readAt: createdAt)),
        startsWith('Read '),
      );
      expect(
        MessageStatusIcon.semanticsLabelFor(mine(deliveredAt: createdAt)),
        startsWith('Delivered '),
      );
    });

    test('a failure says what to do about it', () {
      expect(
        MessageStatusIcon.semanticsLabelFor(mine(status: MessageStatus.failed)),
        contains('retry'),
      );
    });

    testWidgets('the label reaches the semantics tree', (tester) async {
      final handle = tester.ensureSemantics();
      final message = mine(deliveredAt: createdAt, readAt: createdAt);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MessageStatusIcon(message: message)),
      ));

      expect(
        find.bySemanticsLabel(MessageStatusIcon.semanticsLabelFor(message)),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
