import 'package:supabase_flutter/supabase_flutter.dart';

/// True when Supabase silently refused a signup because the campus email already has an account.
///
/// Supabase deliberately does **not** return an error here. Erroring would turn signup into an
/// account-enumeration oracle — anyone could probe which campus addresses are registered. Instead
/// it returns a decoy: a `User` shaped like a fresh signup but with an **empty `identities` list**,
/// and no session. That empty list is the documented signal, and it is the only one available.
///
/// Without this check the app read "no session" as "needs email confirmation" and sent the user to
/// the verify screen to wait for a code that is never sent, because the existing account is
/// already confirmed. The password they just typed was never applied to anything. There was no
/// error, no timeout, and no way forward except guessing.
///
/// Note the deliberate narrowness: a *genuine* new signup awaiting confirmation also has no
/// session, but it carries exactly one identity. Only the empty-list case is a duplicate.
bool isDuplicateSignup(AuthResponse response) {
  if (response.session != null) return false;
  final identities = response.user?.identities;
  return identities != null && identities.isEmpty;
}
