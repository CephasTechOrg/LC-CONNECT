/// Validation + normalization for the optional profile URL fields (LinkedIn, Handshake).
///
/// Pure and dependency-free so it can be unit-tested and reused by the Blueprint Bond editor. The
/// editor used to send whatever was typed straight to the API; a bare `linkedin.com/in/me` has no
/// scheme and opens nowhere when an employer taps it, and genuine typos were saved silently.
library;

/// The outcome of checking one optional URL field.
sealed class UrlFieldResult {
  const UrlFieldResult();
}

/// The field is acceptable. [value] is the normalized string to persist — `''` when the field was
/// left blank (an explicit clear), otherwise an absolute `http(s)` URL with a scheme.
class UrlFieldValid extends UrlFieldResult {
  const UrlFieldValid(this.value);
  final String value;
}

/// The field has content that is not a usable URL. [message] is shown to the user as-is.
class UrlFieldInvalid extends UrlFieldResult {
  const UrlFieldInvalid(this.message);
  final String message;
}

/// Normalize an optional profile URL.
///
/// - Blank → valid, cleared (`''`).
/// - A scheme-less host (`linkedin.com/in/me`) gets `https://` prepended, so it always resolves.
/// - Anything without an `http`/`https` scheme and a dotted host is rejected with [fieldLabel] in
///   the message, so the user learns which field to fix and sees an example.
///
/// Keeping this pure (no I/O, no network) means it is cheap to call on every save and easy to test.
UrlFieldResult normalizeProfileUrl(
  String raw, {
  required String fieldLabel,
  required String example,
}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const UrlFieldValid('');

  var candidate = trimmed;
  if (!candidate.contains('://')) candidate = 'https://$candidate';

  final uri = Uri.tryParse(candidate);
  final looksValid = uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.contains('.');

  if (!looksValid) {
    return UrlFieldInvalid('Enter a valid $fieldLabel URL, e.g. $example');
  }
  return UrlFieldValid(uri.toString());
}
