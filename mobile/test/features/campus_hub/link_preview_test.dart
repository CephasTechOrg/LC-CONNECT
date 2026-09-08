import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/campus_hub/models/campus_post.dart';
import 'package:lc_connect/features/campus_hub/widgets/link_preview_card.dart';

void main() {
  group('LinkPreview.fromJson', () {
    test('parses nested API payload', () {
      final preview = LinkPreview.fromJson({
        'domain': 'jobs.example.com',
        'site_name': 'Example Careers',
        'title': 'Summer Intern',
        'description': 'Join our team.',
        'image_url': 'https://jobs.example.com/poster.jpg',
        'fetched_at': '2026-09-07T12:00:00Z',
        'status': 'ok',
      });
      expect(preview.isOk, isTrue);
      expect(preview.title, 'Summer Intern');
      expect(preview.domain, 'jobs.example.com');
      expect(preview.imageUrl, 'https://jobs.example.com/poster.jpg');
    });

    test('CampusPostSummary keeps null preview when API omits it', () {
      final post = CampusPostSummary.fromJson({
        'id': '11111111-1111-1111-1111-111111111111',
        'kind': 'opportunity',
        'title': 'Role',
        'priority': 'normal',
        'publish_at': '2026-09-07T12:00:00Z',
        'external_url': 'https://jobs.example.com/a',
      });
      expect(post.externalUrl, 'https://jobs.example.com/a');
      expect(post.linkPreview, isNull);
    });

    test('CampusPostSummary parses link_preview object', () {
      final post = CampusPostSummary.fromJson({
        'id': '11111111-1111-1111-1111-111111111111',
        'kind': 'opportunity',
        'title': 'Role',
        'priority': 'normal',
        'publish_at': '2026-09-07T12:00:00Z',
        'external_url': 'https://jobs.example.com/a',
        'link_preview': {
          'domain': 'jobs.example.com',
          'title': 'Summer Intern',
          'status': 'ok',
        },
      });
      expect(post.linkPreview?.title, 'Summer Intern');
    });
  });

  group('linkPreviewHost', () {
    test('extracts hostname', () {
      expect(linkPreviewHost('https://Jobs.Example.com/path'), 'jobs.example.com');
      expect(linkPreviewHost('not a url'), isNull);
    });
  });

  group('LinkPreviewCard', () {
    testWidgets('compact shows OG title and domain', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LinkPreviewCard(
              url: 'https://jobs.example.com/posting/1',
              preview: const LinkPreview(
                domain: 'jobs.example.com',
                title: 'Summer Intern',
                status: 'ok',
              ),
              compact: true,
            ),
          ),
        ),
      );
      expect(find.text('Summer Intern'), findsOneWidget);
      expect(find.text('jobs.example.com'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
    });

    testWidgets('compact falls back to hostname when preview is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LinkPreviewCard(
              url: 'https://careers.livingstone.edu/apply',
              compact: true,
            ),
          ),
        ),
      );
      expect(find.text('careers.livingstone.edu'), findsWidgets);
    });

    testWidgets('expanded shows description and is tappable', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LinkPreviewCard(
              url: 'https://jobs.example.com/posting/1',
              preview: const LinkPreview(
                domain: 'jobs.example.com',
                title: 'Summer Intern',
                description: 'Join our team this summer.',
                status: 'ok',
              ),
              compact: false,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      expect(find.text('Join our team this summer.'), findsOneWidget);
      await tester.tap(find.byType(LinkPreviewCard));
      expect(tapped, isTrue);
    });
  });
}
