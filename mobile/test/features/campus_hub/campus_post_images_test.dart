import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/campus_hub/models/campus_post.dart';
import 'package:lc_connect/features/campus_hub/widgets/campus_post_card.dart';
import 'package:lc_connect/features/campus_hub/widgets/campus_post_image_pager.dart';

CampusPostSummary _summary({List<CampusPostImage> images = const []}) => CampusPostSummary(
  id: '11111111-1111-1111-1111-111111111111',
  kind: 'announcement',
  title: 'Library hours',
  summary: 'Open late this week.',
  priority: 'normal',
  category: 'campus',
  publishAt: DateTime.utc(2026, 10, 21, 12),
  images: images,
);

void main() {
  test('coverUrl is the first image', () {
    final post = CampusPostSummary.fromJson({
      'id': '11111111-1111-1111-1111-111111111111',
      'kind': 'announcement',
      'title': 'Flyer',
      'priority': 'normal',
      'publish_at': '2026-10-21T12:00:00Z',
      'images': [
        {'id': 'a', 'url': 'https://cdn.example/cover.jpg', 'sort_order': 0},
        {'id': 'b', 'url': 'https://cdn.example/two.jpg', 'sort_order': 1},
      ],
    });
    expect(post.coverUrl, 'https://cdn.example/cover.jpg');
    expect(post.images.length, 2);
  });

  test('missing images defaults to empty', () {
    final post = CampusPostSummary.fromJson({
      'id': '11111111-1111-1111-1111-111111111111',
      'kind': 'announcement',
      'title': 'No photos',
      'priority': 'normal',
      'publish_at': '2026-10-21T12:00:00Z',
    });
    expect(post.images, isEmpty);
    expect(post.coverUrl, isNull);
  });

  testWidgets('list card uses icon fallback when there is no cover', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CampusPostCard(post: _summary(), onTap: () {}),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('campus-post-icon')), findsOneWidget);
    expect(find.byKey(const ValueKey('campus-post-cover')), findsNothing);
  });

  testWidgets('list card shows cover when the post has images', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CampusPostCard(
            post: _summary(
              images: const [
                CampusPostImage(id: 'a', url: 'https://cdn.example/cover.jpg', sortOrder: 0),
              ],
            ),
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('campus-post-cover')), findsOneWidget);
    expect(find.byKey(const ValueKey('campus-post-icon')), findsNothing);
  });

  testWidgets('detail pager labels 2+ images', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CampusPostImagePager(
            postId: 'post-1',
            images: [
              CampusPostImage(id: 'a', url: 'https://cdn.example/one.jpg', sortOrder: 0),
              CampusPostImage(id: 'b', url: 'https://cdn.example/two.jpg', sortOrder: 1),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('campus-post-image-pager')), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
  });
}
