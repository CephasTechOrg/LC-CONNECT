LC Connect — Mobile UI Redesign Brief
Status: Design and implementation proposal. No repository files have been modified.

Grounding: Four iPhone screenshots shared October 20, 2026, plus a read-only review of the main branch of CephasTechOrg/LC-CONNECT, focusing on mobile/lib/.
Executive direction
Retain LC Connect's identity (school blue, campus identity, existing routes and features) but move from card-heavy compositions to a clean, student-centered interface with consistent information hierarchy. Do not imitate the content model of a fintech product. Borrow restraint, spacing, grid discipline, and component reuse.

North star: On Campus, prioritize personalized context and current actionable information; on Connect, let users scan multiple students without navigating dense cards; in Chat, let the conversation—not bubble chrome—dominate.
Verified architecture facts
- App uses Flutter + Material 3, Riverpod and GoRouter.
- Existing token foundations exist: core/theme/app_spacing.dart, app_typography.dart, app_radii.dart, app_shadows.dart, and app_theme.dart.
- AppSpacing.gutter already equals 20 logical pixels; scale is 4/8/12/16/20/24/32.
- AppTypography defines 10 role-based type sizes; nevertheless, several examined feature widgets still hardcode GoogleFonts.dmSans(fontSize: ...) and individual paddings. This is a consistency / adoption problem, not an absence of tokens.
- Home dashboard is composed by CampusHubScreen, including greeting, conditional Blueprint/attendance prompts, spotlight carousel, quick actions, announcements, activities, and suggested connections.
- CampusQuickAction uses three bordered shadowed cards; _LatestUpdatesPanel always uses a gradient panel even when no updates exist.
- Discovery student cards render: identity, intent badges, interest chips, languages, match text, two primary-looking CTAs when study intent exists, and Maybe Later.
- Chat bubbles display the DM partner's avatar for every incoming message; bubble shadows and timestamps introduce visual noise.
- chat_input.dart wraps a TextField in a bordered container while the global InputDecorationTheme specifies enabled/focused outlines; explicitly disable all inner input borders or unify the border into a single decoration to avoid double outlines.
- Navigation already uses a shared NavShell and an accessible selected-tab semantics pattern; retain these features.
Redesigned information architecture
Campus home — proposed order
1. Greeting and notifications: compact branded header, user identity in a clear type hierarchy.
2. Contextual prompts: profile completion or attendance as compact rows only when relevant; do not permanently occupy hero-level space.
3. Campus spotlight: preserve existing real campaign images, short headline and one actionable CTA; optimize composition and height, do not simply shrink text.
4. Quick access: three unboxed, equally aligned icon-with-label shortcuts for Directory, Resources, Opportunities, with opportunity badge if present.
5. Campus updates: normal text/list section; show the stronger featured treatment only if there is a meaningful, nonurgent update. Preserve urgent notices with distinct higher priority.
6. Upcoming activities: compact dated rows with status and location. For no-data, one line, not a large panel.
7. Suggested connections: compact student rows/previews; preserve route to public profile.
Connect — proposed result row hierarchy
- Top row: avatar (48–52dp), name (16sp semibold/bold), class year and major (13sp secondary), overflow actions.
- Secondary content: at most one visible match reason and one brief interest/intent line. The public profile remains the location for full tags, languages, and other details.
- Actions: one primary Connect action and a visibly differentiated secondary Study together action only when eligible. Preserve Maybe Later in a discoverable accessible overflow/action sheet or equivalent user-tested interaction.
- Avoid outer rounded card framing for every student; rows can use a hairline separator and 12–16dp spacing.
- Preserve filters, search behavior, ValueKey(profileId), loading, error, retry, and pending state semantics.
Chat — proposed changes
- Compact header with back control, avatar/name, context, and overflow; tappable profile retained.
- Group messages by sender/time run; in DMs, show avatar once per received run instead of every incoming bubble. Keep sender identity logic for groups.
- Tighten intra-run spacing to ~3–4dp and inter-run spacing to ~12–16dp; choose grouping thresholds intentionally and test with different timestamps and deleted messages.
- Remove resting drop shadows from bubbles and reduce unnecessary borders; outgoing brand-blue, incoming pale neutral.
- Use one rounded composer with exactly one border or none, proper 44/48dp hit targets, multiline input, keyboard-safe padding, and disabled state only when truly necessary.
- Preserve optimistic send, delivery receipts, edit/delete, reactions, retries, accessibility, and group-specific behavior.
Proposed design parameters (initial targets, not a substitute for simulator validation)
Area	Proposal
Baseline grid	Existing 4dp token scale
Horizontal gutters	Preserve 20dp (AppSpacing.gutter)
Vertical page sections	Mostly 20–28dp, chosen by relationship
Text hierarchy	Use AppTypography roles, avoid new arbitrary sizes
Primary body text	14–16sp depending on component; support system text scaling
Metadata	12–13sp where contrast/accessibility permit
Surfaces	AppColors.surface / AppColors.background; emphasize through contrast rather than many containers
Borders	1dp low-contrast dividers for actual boundaries; not around every row
Radii	Use named AppRadii roles
Elevation	Shadows only for real layering; do not shadow all cards
Tap targets	≥44×44 logical pt on iOS and ≥48×48dp on Android when applicable
Student result density	Aim to reveal ~2–3 useful profiles on a typical phone before scrolling, depending on font scaling and viewport
Animation	Respect reduced-motion preference and user-controlled carousels
Contrast	Target WCAG AA for readable text/control states (verify actual rendered combinations)
Empty state	Small informative row on dashboards; fuller illustrated state only for dedicated empty screens


Component architecture: adapt, don't duplicate
Keep existing AppTheme, AppColors, AppSpacing, AppTypography, AppRadii, AppShadows, NavShell, and current route/provider boundaries. Add/refine only components repeatedly needed across multiple features:
- AppSectionHeader with title/action/accessibility semantics (replace duplicated local section headers).
- AppQuickAction with icon, label, optional badge and consistent hit area.
- CompactStudentRow / StudentIdentity shared between Campus suggestions and Connect results, with explicit variants rather than divergent reimplementations.
- CampusUpdatePreview, ActivityPreviewRow, and shared dashboard empty-state row.
- ChatComposer with a single decoration and semantic send button.
- MessageRun presentation helper that calculates group starts and ends without rewriting delivery state.
Only abstract components that represent a repeatable visual/behavioral pattern. Do not prematurely merge unlike domain components.
Implementation stages and acceptance gates
Phase 0 — Baseline and safety
- [ ] Capture golden screenshots for Home, Connect, Chat at minimum one iPhone and one small Android viewport.
- [ ] Document loading/empty/error/populated states, increased text size, and scroll position.
- [ ] Inventory which existing tokens are used vs hardcoded, with grep/search results.
- [ ] Verify all current behaviors, routes, badges, unread counts, notification handling, and role-gated content.
Phase 1 — Reusable visual primitives
- [ ] Establish a shared section header / empty preview row / quick action style.
- [ ] Use existing typography, spacing and radius roles, replacing selected one-off values.
- [ ] Introduce no global button height reduction without checking all screens.
- [ ] Add UI golden/widget tests; pass flutter analyze and relevant tests.
Phase 2 — Campus home
- [ ] Preserve greeting, notifications, conditional Blueprint Bond/attendance, carousel, urgent/latest updates, quick actions, activities and suggested connections.
- [ ] Make profile/attendance prompts compact and contextual.
- [ ] Reduce vertical noise in the spotlight and quick actions.
- [ ] Implement lighter announcement empty state and compact activity previews.
- [ ] Visually test both populated and empty states.
Phase 3 — Connect
- [ ] Rebuild _StudentCard around information hierarchy; retain existing callbacks and eligibility.
- [ ] Keep Connect, conditional Study Together, Maybe Later, and report/block actions accessible.
- [ ] Preserve multiple filters, search, loading/acting states and referral to full public profiles.
- [ ] Validate long names, long major labels, translations, screen reader semantics, 200% text scale, 320px viewports.
Phase 4 — Messaging
- [ ] Fix duplicate input border with explicit decoration ownership.
- [ ] Group DM message runs and avoid repeating avatars without losing sender clarity.
- [ ] Tune timestamps, bubble borders, spacing and composer.
- [ ] Run message send, retry, draft, edit/delete, read receipt and reaction tests.
- [ ] Test keyboard open/close, scroll-to-bottom, safe area and slow-network sends.
Phase 5 — System-wide visual validation
- [ ] Confirm gutters and navigation consistency across all five main tabs.
- [ ] Verify iOS/Android and small/large screens, portrait landscape where supported, enlarged text, screen reader labels, and contrast.
- [ ] Compare screenshot diffs with baseline, checking there are no clipped/overflowing widgets.
- [ ] Manually sign off UX flow and only then merge the feature branch into develop/main according to the repo workflow.
Source files checked
- mobile/lib/core/theme/app_theme.dart
- mobile/lib/core/theme/app_spacing.dart
- mobile/lib/core/theme/app_typography.dart
- mobile/lib/features/campus_hub/screens/campus_hub_screen.dart
- mobile/lib/features/campus_hub/widgets/campus_quick_action.dart
- mobile/lib/features/campus_hub/widgets/campus_updates_panel.dart
- mobile/lib/features/discovery/widgets/discovery_student_card.dart
- mobile/lib/features/messages/widgets/chat_input.dart
- mobile/lib/features/messages/widgets/chat_bubble.dart
- mobile/lib/shared/widgets/nav_shell.dart
Scope of review: Screenshots and these repository files, not a full app audit or running Flutter build. Confirm behavior in simulator during implementation. The redesign image is an illustrative target, not a pixel-perfect implementation preview; student names and activities are sample content and the logo is a placeholder.