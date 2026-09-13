import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lc_connect/core/api/api_client.dart';
import 'package:lc_connect/features/policies/data/policy_slugs.dart';
import 'package:lc_connect/features/policies/screens/policy_document_screen.dart';
import 'package:lc_connect/features/policies/widgets/policy_links.dart';

/// Serves the **real** markdown from `docs/policies/`, so these tests exercise the documents that
/// actually ship rather than a stub that cannot reproduce their tables and blockquotes.
ApiClient _clientServingRealDocs({Set<String> failFor = const {}}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
  dio.httpClientAdapter = _RealDocsAdapter(failFor: failFor);
  return ApiClient(dio: dio);
}

class _RealDocsAdapter implements HttpClientAdapter {
  final Set<String> failFor;
  _RealDocsAdapter({required this.failFor});

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    final slug = options.path.split('/').last;
    if (failFor.contains(slug)) {
      return ResponseBody.fromString('{"detail":"boom"}', 500,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    // Tests run from `mobile/`, so the repo's docs are one level up.
    final file = File('../docs/policies/$slug.md');
    if (!file.existsSync()) {
      return ResponseBody.fromString('{"detail":"not found"}', 404,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    final body = file.readAsStringSync();
    final title = body
        .split('\n')
        .firstWhere((l) => l.startsWith('# '), orElse: () => '# $slug')
        .substring(2)
        .replaceFirst('LC Connect — ', '')
        .trim();
    return ResponseBody.fromString(
      '{"slug":"$slug","title":${_json(title)},"version":$kPolicyVersion,"body":${_json(body)}}',
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  static String _json(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n').replaceAll('\r', '')}"';

  @override
  void close({bool force = false}) {}
}

Future<void> _pumpReader(WidgetTester tester, String slug, {ApiClient? client}) async {
  final router = GoRouter(initialLocation: '/policies/$slug', routes: [
    GoRoute(path: '/login', builder: (c, s) => const Scaffold(body: Text('login'))),
    GoRoute(
      path: '/policies/:slug',
      builder: (c, s) => PolicyDocumentScreen(slug: s.pathParameters['slug']!),
    ),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client ?? _clientServingRealDocs()),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => dotenv.loadFromString(
      envString: 'API_BASE_URL=http://test/api/v1\nENV=test'));

  group('policy reader', () {
    testWidgets('renders the real Terms of Service as markdown', (tester) async {
      await _pumpReader(tester, PolicySlug.terms);
      expect(find.byType(Markdown), findsOneWidget);
      expect(find.text('Terms of Service'), findsWidgets); // app bar title
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders the Privacy Policy, tables and all', (tester) async {
      // The privacy policy is the table-heavy one — an unstyled or crashing table would be worst
      // exactly where a reader most needs to scan (what we store, how long we keep it).
      await _pumpReader(tester, PolicySlug.privacy);
      expect(find.byType(Markdown), findsOneWidget);
      expect(find.byType(Table), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders the Community Guidelines', (tester) async {
      await _pumpReader(tester, PolicySlug.guidelines);
      expect(find.byType(Markdown), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a load failure offers a retry instead of a blank page', (tester) async {
      await _pumpReader(
        tester,
        PolicySlug.terms,
        client: _clientServingRealDocs(failFor: {PolicySlug.terms}),
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(Markdown), findsNothing);
    });

    testWidgets('the back arrow is always present', (tester) async {
      await _pumpReader(tester, PolicySlug.terms);
      expect(find.byTooltip('Back'), findsOneWidget);
    });
  });

  group('policy links', () {
    testWidgets('the linked pair opens the reader and can come back', (tester) async {
      final router = GoRouter(initialLocation: '/host', routes: [
        GoRoute(
          path: '/host',
          builder: (c, s) => Scaffold(
            body: Center(
              child: RichText(
                text: TextSpan(children: policyPairSpans(c)),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/policies/:slug',
          builder: (c, s) => PolicyDocumentScreen(slug: s.pathParameters['slug']!),
        ),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(_clientServingRealDocs())],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();

      // Both names are present in one sentence, not as separate buttons.
      expect(find.textContaining('Terms of Service', findRichText: true), findsOneWidget);
      expect(find.textContaining('Privacy Policy', findRichText: true), findsOneWidget);

      await tester.tapOnText(find.textRange.ofSubstring('Privacy Policy'));
      await tester.pumpAndSettle();
      expect(find.byType(PolicyDocumentScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(PolicyDocumentScreen), findsNothing);
    });

    testWidgets('the stacked list offers all three documents', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: const Scaffold(body: PolicyLinkList()),
        ),
      ));
      await tester.pump();
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Community Guidelines'), findsOneWidget);
    });
  });

  test('the app version matches the backend constant', () {
    // A drift here is how a user gets re-prompted forever, or silently treated as having accepted
    // a policy they never saw. The backend clamps, so mismatch fails safe — but it should not
    // happen at all.
    final backend = File('../backend/app/shared/policy_versions.py').readAsStringSync();
    expect(backend, contains('CURRENT_POLICY_VERSION = $kPolicyVersion'));
  });
}
