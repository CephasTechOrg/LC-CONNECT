/// Resolves the name the Home greeting shows.
///
/// Order: the first word of the loaded profile's display name (the freshest — it reflects a rename
/// made in this session), else the display name bootstrap returned at sign-in, else the first name
/// given at signup, else the campus address (email local part), else `there`.
///
/// Bootstrap finishes before the splash clears, so the second source is in memory on Home's first
/// frame. This used to wait for `/profiles/me` instead and showed "there" until it arrived — a
/// placeholder on every launch, to avoid a stale name that only a rename on another device could
/// cause.
String resolveGreetingName({
  String? profileDisplayName,
  String? accountDisplayName,
  String? firstName,
  String? email,
}) {
  for (final candidate in [profileDisplayName, accountDisplayName]) {
    final name = candidate?.trim();
    if (name != null && name.isNotEmpty) return name.split(RegExp(r'\s+')).first;
  }
  final fromSignup = firstName?.trim();
  if (fromSignup != null && fromSignup.isNotEmpty) return fromSignup;
  final raw = email?.split('@').first;
  if (raw == null || raw.isEmpty) return 'there';
  return raw[0].toUpperCase() + raw.substring(1);
}
