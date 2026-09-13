import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

class PolicyDocument {
  final String slug;
  final String title;
  final int version;
  final String body;

  const PolicyDocument({
    required this.slug,
    required this.title,
    required this.version,
    required this.body,
  });

  factory PolicyDocument.fromJson(Map<String, dynamic> json) => PolicyDocument(
        slug: json['slug'] as String,
        title: json['title'] as String,
        version: json['version'] as int? ?? 0,
        body: json['body'] as String? ?? '',
      );
}

/// One policy document, by slug.
///
/// `/policies/{slug}` is unauthenticated on purpose — the signup screen links into these before an
/// account exists, so this must work with no session.
///
/// `keepAlive` because a document is a few kilobytes of text that does not change between app
/// launches, and the likely path is: read the terms, go back, read the privacy policy, go back,
/// accept. Re-fetching on each of those would show a spinner over text the user just had.
final policyDocumentProvider =
    FutureProvider.family<PolicyDocument, String>((ref, slug) async {
  ref.keepAlive();
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/policies/$slug');
  return PolicyDocument.fromJson(response.data as Map<String, dynamic>);
});
