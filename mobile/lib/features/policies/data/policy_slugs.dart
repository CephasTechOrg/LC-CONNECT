/// The policy documents the app links to, and the version it asks users to accept.
///
/// [kPolicyVersion] must match `CURRENT_POLICY_VERSION` in
/// `backend/app/shared/policy_versions.py`. The app sends this value through signup metadata; the
/// backend clamps anything higher than its own constant, so a mismatch fails safe — the user is
/// simply re-prompted rather than silently treated as having accepted something newer.
const int kPolicyVersion = 1;

/// Slugs served by `GET /api/v1/policies/{slug}`.
class PolicySlug {
  static const terms = 'terms-of-service';
  static const privacy = 'privacy-policy';
  static const guidelines = 'community-guidelines';

  /// The two a user must accept to use the app. The community guidelines are part of the terms by
  /// reference, and linked from the app, but are not a separate acceptance.
  static const requiredForApp = [terms, privacy];
}
