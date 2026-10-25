/// First and last name rules for the signup form.
///
/// Mirrors `backend/app/shared/person_names.py`, which the server enforces at signup (the Send
/// Email hook refuses a new signup without both names) and again when it stores them. Checking
/// here first means a student sees which field to fix instead of a generic signup failure.
const int kMaxNameLength = 50;

// Letters in any script, combining accents, and the punctuation real names use:
// "Mary-Jane", "O'Neil", "N’Golo", "St. John".
final _nameChars = RegExp(r"^[\p{L}\p{M} \-'.’]+$", unicode: true);
final _letter = RegExp(r'\p{L}', unicode: true);

/// Trimmed, single-spaced — the same tidy-up the server applies before storing.
String normalizePersonName(String raw) => raw.trim().split(RegExp(r'\s+')).join(' ');

/// A form validator: null when [value] is a usable name, else the message to show under the field.
String? validatePersonName(String? value, {required String field}) {
  final name = normalizePersonName(value ?? '');
  if (name.isEmpty) return 'Enter your $field';
  if (name.length > kMaxNameLength) return 'Keep it to $kMaxNameLength characters';
  if (!_letter.hasMatch(name) || !_nameChars.hasMatch(name)) {
    return 'Use letters, spaces, hyphens or apostrophes';
  }
  return null;
}
