/// Resolves the name the Home greeting shows.
///
/// Order: the first word of the student's *current saved* profile display name, else the first
/// name given at signup, else the campus address (email local part), else `there`. The editable
/// profile name is the student's live identity, so it wins over the signup name, which goes stale
/// after a rename — that mismatch was the "old name" testers saw flash before it corrected.
///
/// Returns `null` until the profile has resolved ([profileResolved] is false): before that there
/// is no authoritative name, and deriving one from the email only to replace it a frame later is
/// the flicker to avoid. Callers hold the previously resolved name while this returns null.
String? resolveGreetingName({
  String? firstName,
  String? displayName,
  String? email,
  required bool profileResolved,
}) {
  if (!profileResolved) return null;
  final fromProfile = displayName?.trim();
  if (fromProfile != null && fromProfile.isNotEmpty) {
    return fromProfile.split(RegExp(r'\s+')).first;
  }
  final fromSignup = firstName?.trim();
  if (fromSignup != null && fromSignup.isNotEmpty) return fromSignup;
  final raw = email?.split('@').first;
  if (raw == null || raw.isEmpty) return 'there';
  return raw[0].toUpperCase() + raw.substring(1);
}
