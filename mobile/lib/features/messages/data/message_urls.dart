/// URL detection for chat bodies and the composer. Mirrors backend `first_http_url` so a
/// pasted `https://example.com.` still unfurls instead of 404ing on the trailing period.
library;

final _urlInText = RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false);
const _trailingPunct = ".,);:!?]'";

String _stripTrailingPunct(String url) {
  var out = url;
  while (out.isNotEmpty && _trailingPunct.contains(out[out.length - 1])) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

/// The first http(s) URL in [text], or null. Trailing sentence punctuation is stripped.
String? firstHttpUrl(String text) {
  final match = _urlInText.firstMatch(text);
  if (match == null) return null;
  final url = _stripTrailingPunct(match.group(0)!);
  return url.isEmpty ? null : url;
}

/// One run of a chat body: either plain text or a URL.
class MessageTextRun {
  const MessageTextRun(this.text, {this.isUrl = false});
  final String text;
  final bool isUrl;
}

/// Split [text] into plain runs and URL runs so the bubble can underline only the links.
List<MessageTextRun> splitMessageLinks(String text) {
  final runs = <MessageTextRun>[];
  var cursor = 0;
  for (final match in _urlInText.allMatches(text)) {
    if (match.start > cursor) {
      runs.add(MessageTextRun(text.substring(cursor, match.start)));
    }
    final raw = match.group(0)!;
    final url = _stripTrailingPunct(raw);
    final trailing = raw.substring(url.length);
    if (url.isNotEmpty) runs.add(MessageTextRun(url, isUrl: true));
    if (trailing.isNotEmpty) runs.add(MessageTextRun(trailing));
    cursor = match.end;
  }
  if (cursor < text.length) runs.add(MessageTextRun(text.substring(cursor)));
  return runs;
}
