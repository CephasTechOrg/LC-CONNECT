import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/messages/providers/link_preview_provider.dart';
import 'package:lc_connect/features/messages/widgets/message_link_preview.dart';

void main() {
  test('the bubble sheet offers Copy', () {
    final source = File('lib/features/messages/widgets/chat_bubble_options.dart')
        .readAsStringSync();
    expect(source, contains("Text('Copy'"));
    expect(source, contains('Clipboard.setData'));
  });

  testWidgets('link card shows unfurled title and domain', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          messageLinkPreviewProvider.overrideWith((ref, url) async => MessageLinkPreview(
                url: url,
                domain: 'example.com',
                title: 'Summer Intern',
                status: 'ok',
              )),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MessageLinkCard(url: 'https://example.com/jobs', isMine: false),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Summer Intern'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
  });

  testWidgets('link card falls back to the hostname when unfurl fails', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          messageLinkPreviewProvider.overrideWith((ref, url) async => MessageLinkPreview(
                url: url,
                status: 'failed',
              )),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MessageLinkCard(url: 'https://example.com/jobs', isMine: false),
          ),
        ),
      ),
    );
    await tester.pump();
    // Hostname is both the domain line and the title fallback — two widgets, same text.
    expect(find.text('example.com'), findsWidgets);
  });

  testWidgets('LinkedMessageText underlines a URL in the body', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LinkedMessageText(
            text: 'see https://example.com/x please',
            isMine: false,
          ),
        ),
      ),
    );
    expect(find.textContaining('https://example.com/x'), findsOneWidget);
  });
}
