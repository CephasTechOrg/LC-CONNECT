import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/widgets/avatar_preview.dart';
import 'package:lc_connect/core/widgets/avatar_widget.dart';

/// Report #3 — "profile-picture viewing is limited". Before this there was no full-screen viewer
/// anywhere in the app: `Hero`, `InteractiveViewer` and `photo_view` returned zero hits.
///
/// The tests that matter most here are the *negative* ones. Attaching a viewer to every avatar is
/// the obvious move and the wrong one — it would steal the tap from list rows whose job is to
/// navigate to the person.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

  /// Advances past the route transition without waiting for the tree to go idle.
  ///
  /// The viewer's placeholder is a `CircularProgressIndicator`, which animates forever — the
  /// image can never load in a test — so `pumpAndSettle` times out rather than settling.
  Future<void> settleRoute(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('the preview is opt-in', () {
    testWidgets('an avatar without a tag is not tappable', (tester) async {
      // The default, and deliberately so: most avatars sit in a row that navigates.
      await tester.pumpWidget(host(
        const AvatarWidget(imageUrl: 'https://example.test/a.jpg', size: 80),
      ));

      expect(find.byType(GestureDetector), findsNothing);
      expect(find.byType(Hero), findsNothing);
    });

    testWidgets('an avatar with a tag is tappable', (tester) async {
      await tester.pumpWidget(host(
        const AvatarWidget(
          imageUrl: 'https://example.test/a.jpg',
          size: 80,
          previewHeroTag: 'avatar:u1',
        ),
      ));

      expect(find.byType(GestureDetector), findsWidgets);
      expect(find.byType(Hero), findsOneWidget);
    });

    testWidgets('an avatar with no photo is never tappable, even when tagged', (tester) async {
      // A viewer showing the fallback silhouette full-screen offers nothing, and an avatar that
      // opens *sometimes* is worse than one that never does.
      await tester.pumpWidget(host(
        const AvatarWidget(size: 80, previewHeroTag: 'avatar:u1'),
      ));

      expect(find.byType(Hero), findsNothing);
    });

    testWidgets('an empty photo URL counts as no photo', (tester) async {
      await tester.pumpWidget(host(
        const AvatarWidget(imageUrl: '', size: 80, previewHeroTag: 'avatar:u1'),
      ));

      expect(find.byType(Hero), findsNothing);
    });
  });

  group('opening and closing', () {
    testWidgets('tapping a tagged avatar opens the viewer', (tester) async {
      await tester.pumpWidget(host(
        const AvatarWidget(
          imageUrl: 'https://example.test/a.jpg',
          size: 80,
          previewHeroTag: 'avatar:u1',
          previewName: 'Maya Chen',
        ),
      ));

      await tester.tap(find.byType(AvatarWidget));
      await settleRoute(tester);

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });

    testWidgets('the close button meets the minimum tap target', (tester) async {
      await tester.pumpWidget(host(
        const AvatarWidget(
          imageUrl: 'https://example.test/a.jpg',
          size: 80,
          previewHeroTag: 'avatar:u1',
        ),
      ));
      await tester.tap(find.byType(AvatarWidget));
      await settleRoute(tester);

      // A default IconButton is 40dp — under the 48 this needs.
      final size = tester.getSize(find.byIcon(Icons.close_rounded).hitTestable());
      expect(size.width, greaterThanOrEqualTo(24));
      final button = tester.getSize(find.ancestor(
        of: find.byIcon(Icons.close_rounded),
        matching: find.byType(IconButton),
      ));
      expect(button.width, greaterThanOrEqualTo(48));
      expect(button.height, greaterThanOrEqualTo(48));
    });

    testWidgets('the close button dismisses it', (tester) async {
      await tester.pumpWidget(host(
        const AvatarWidget(
          imageUrl: 'https://example.test/a.jpg',
          size: 80,
          previewHeroTag: 'avatar:u1',
        ),
      ));
      await tester.tap(find.byType(AvatarWidget));
      await settleRoute(tester);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await settleRoute(tester);

      expect(find.byType(InteractiveViewer), findsNothing);
    });

    testWidgets('the photo can be pinch-zoomed', (tester) async {
      // The actual request in report #3 — seeing the photo properly, not just bigger.
      await tester.pumpWidget(host(
        const AvatarWidget(
          imageUrl: 'https://example.test/a.jpg',
          size: 80,
          previewHeroTag: 'avatar:u1',
        ),
      ));
      await tester.tap(find.byType(AvatarWidget));
      await settleRoute(tester);

      final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(viewer.maxScale, greaterThan(1));
    });
  });

  group('accessibility', () {
    testWidgets('the avatar says what tapping it does', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(
        const AvatarWidget(
          imageUrl: 'https://example.test/a.jpg',
          size: 80,
          previewHeroTag: 'avatar:u1',
          previewName: 'Maya Chen',
        ),
      ));

      // Without this the avatar is an unlabelled tappable circle.
      expect(
        find.bySemanticsLabel("Maya Chen's profile photo, double tap to view"),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('an unnamed avatar still has a usable label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(
        const AvatarWidget(
          imageUrl: 'https://example.test/a.jpg',
          size: 80,
          previewHeroTag: 'avatar:u1',
        ),
      ));

      expect(find.bySemanticsLabel('Profile photo, double tap to view'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the open viewer labels the photo and the close control', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(
        const AvatarWidget(
          imageUrl: 'https://example.test/a.jpg',
          size: 80,
          previewHeroTag: 'avatar:u1',
          previewName: 'Maya Chen',
        ),
      ));
      await tester.tap(find.byType(AvatarWidget));
      await settleRoute(tester);

      expect(find.bySemanticsLabel("Maya Chen's profile photo"), findsWidgets);
      expect(find.bySemanticsLabel('Close photo'), findsWidgets);
      handle.dispose();
    });
  });

  group('showAvatarPreview directly', () {
    testWidgets('it can be opened without an AvatarWidget', (tester) async {
      // The chat header and other bespoke avatars render their own image; the helper has to work
      // for them too rather than being reachable only through one widget.
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          ctx = context;
          return const Scaffold(body: SizedBox());
        }),
      ));

      showAvatarPreview(ctx, imageUrl: 'https://example.test/a.jpg', heroTag: 'x');
      await settleRoute(tester);

      expect(find.byType(InteractiveViewer), findsOneWidget);
    });
  });
}
