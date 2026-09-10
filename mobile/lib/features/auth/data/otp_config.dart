/// Length of the one-time codes Supabase emails for signup confirmation and password recovery.
///
/// Supabase generates these codes, so the length is a **project setting in the Supabase dashboard**
/// (Authentication → Providers → Email → OTP length), not something the app controls. It is
/// declared once here because it was previously retyped as a literal on three screens, and the
/// copy, the validators and the tests drifted apart — the app said "8-digit" while a test still
/// asserted "6-digit".
///
/// If the dashboard setting ever changes, change it here and nowhere else.
/// See docs/getting-started/supabase.md.
const int kOtpLength = 8;
