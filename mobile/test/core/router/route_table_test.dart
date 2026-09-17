import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/core/router/app_routes.dart';
import 'package:lc_connect/features/messages/utils/chat_routes.dart';

/// Structural assertions on the route table, matched without building any screen.
///
/// Whether a route sits inside the navigation shell is not a cosmetic detail:
///
///  * Report #2 — a conversation inside the shell renders the bottom navigation bar underneath
///    its own full-screen header, two scaffolds deep.
///  * Stability — chat pushes *top-level* routes (a group sender's avatar opens
///    `/users/:profileId`, the header opens `/groups/:groupId`). That same cross-navigator push
///    from inside the shell is what locked the navigator for `/connections` and
///    `/profile/blueprint-bond`, and it reached users as the app appearing to sign out.
///
/// A widget test cannot state either of those as a property — it can only show that one
/// particular screen currently has no nav bar. This states the shape.
void main() {
  // `GoRouter.configuration.findMatch` resolves a location against the real table without a
  // BuildContext, so nothing has to be initialised — no Supabase, no providers, no pumping.
  final configuration = GoRouter(routes: appRoutes()).configuration;

  /// The matched route stack for [location], outermost first.
  ///
  /// Flattened recursively: a [ShellRouteMatch] holds its children in its own `matches`, so the
  /// top-level list alone reports a shell route as the innermost match.
  List<RouteBase> stackFor(String location) {
    final stack = <RouteBase>[];
    void visit(Iterable<RouteMatchBase> matches) {
      for (final match in matches) {
        stack.add(match.route);
        if (match is ShellRouteMatch) visit(match.matches);
      }
    }

    visit(configuration.findMatch(Uri.parse(location)).matches);
    return stack;
  }

  bool isInsideShell(String location) => stackFor(location).any((r) => r is ShellRoute);

  group('conversations are outside the navigation shell', () {
    test('a DM conversation', () {
      expect(stackFor(dmChatPath('match-1')), isNotEmpty, reason: 'the route must exist');
      expect(isInsideShell(dmChatPath('match-1')), isFalse);
    });

    test('a group conversation', () {
      expect(stackFor(groupChatPath('conv-1')), isNotEmpty);
      expect(isInsideShell(groupChatPath('conv-1')), isFalse);
    });

    test('a group conversation id is never matched as a DM id', () {
      // `/chat/group/:conversationId` is two segments and is declared first, but a table where
      // `/chat/:matchId` won would silently open every group as a DM — the exact failure the
      // notification path already had.
      final groupStack = stackFor(groupChatPath('conv-1'));
      final dmStack = stackFor(dmChatPath('match-1'));
      expect(groupStack.last, isNot(same(dmStack.last)));
    });
  });

  group('list-like surfaces stay inside the shell', () {
    test('the conversation list', () {
      expect(isInsideShell(messagesPath), isTrue);
    });

    test('the recipient picker', () {
      // A picker is a list, not a conversation: it keeps the tab bar.
      expect(isInsideShell(newMessagePath), isTrue);
    });
  });

  group('legacy conversation locations still resolve', () {
    // Push payloads already on devices, and links users have saved, point at these. A tap on one
    // must reach the conversation, not an error route.
    test('the legacy DM location matches a route carrying a redirect', () {
      final stack = stackFor('/messages/match-1');
      expect(stack, isNotEmpty);
      expect(stack.last, isA<GoRoute>());
      expect((stack.last as GoRoute).redirect, isNotNull,
          reason: 'without a redirect this location would render the old in-shell chat');
    });

    test('the legacy group location matches a route carrying a redirect', () {
      final stack = stackFor('/messages/group/conv-1');
      expect((stack.last as GoRoute).redirect, isNotNull);
    });

    test('the redirects point at the new locations', () {
      expect(dmChatPath('match-1'), '/chat/match-1');
      expect(groupChatPath('conv-1'), '/chat/group/conv-1');
    });

    test('the legacy DM pattern does not swallow the static children beside it', () {
      // `:matchId` is declared last for this reason. If it won, '/messages/new' would redirect
      // to a conversation called "new".
      final picker = stackFor(newMessagePath);
      expect((picker.last as GoRoute).redirect, isNull);
    });
  });

  group('the Messages hub has a Groups half', () {
    test('Groups is a route under Messages, not a query parameter', () {
      // A nested route rather than `?tab=groups`: back behaviour is correct, the location is
      // deep-linkable, and it survives the app being killed and restored.
      expect(stackFor(groupsPath), isNotEmpty);
      expect(groupsPath, '/messages/groups');
    });

    test('Groups is inside the shell, so it keeps the tab bar', () {
      // Unlike a conversation, this is a list-like browsing surface and belongs in a tab.
      expect(isInsideShell(groupsPath), isTrue);
    });

    test('Groups is not reachable through the Discovery tab any more', () {
      // Report #19's real bug: Discovery returns the staff directory outright for any
      // non-student role, so staff had no route to groups at all — even though the backend
      // deliberately opens groups to staff. Messages is not role-gated.
      final stack = stackFor('/discover?tab=groups');
      final discover = stack.last as GoRoute;
      expect(discover.redirect, isNotNull,
          reason: 'the old location must forward, not render a segment that no longer exists');
    });

    test('plain /discover is not redirected', () {
      // The redirect is conditional on the query parameter; the Connect tab itself must still
      // render, or the second navigation tab becomes unreachable.
      final stack = stackFor('/discover');
      expect((stack.last as GoRoute).builder, isNotNull);
    });

    test('Chats and Groups are siblings of one destination', () {
      // Both live under '/messages', which is what makes the segment switch a `go` between
      // peers rather than a push onto a growing stack.
      expect(groupsPath.startsWith('$messagesPath/'), isTrue);
    });
  });
}
