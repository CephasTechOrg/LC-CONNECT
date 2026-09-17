import 'package:go_router/go_router.dart';

import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/verify_email_screen.dart';
import '../../features/auth/screens/suspended_screen.dart';
import '../../features/campus_hub/screens/campus_hub_screen.dart';
import '../../features/campus_hub/screens/campus_directory_screen.dart';
import '../../features/campus_hub/screens/campus_position_detail_screen.dart';
import '../../features/campus_hub/screens/campus_updates_screen.dart';
import '../../features/campus_hub/screens/campus_opportunities_screen.dart';
import '../../features/campus_hub/screens/campus_post_detail_screen.dart';
import '../../features/campus_hub/screens/campus_resources_screen.dart';
import '../../features/campus_hub/screens/compose_campus_post_screen.dart';
import '../../features/campus_hub/screens/my_campus_posts_screen.dart';
import '../../features/campus_hub/providers/campus_publishing_provider.dart';
import '../../features/discovery/screens/discovery_screen.dart';
import '../../features/activities/screens/activities_screen.dart';
import '../../features/activities/screens/activity_detail_screen.dart';
import '../../features/activities/screens/create_activity_screen.dart';
import '../../features/activities/providers/activities_provider.dart';
import '../../features/messages/screens/chat_screen.dart';
import '../../features/messages/screens/messages_screen.dart';
import '../../features/messages/screens/groups_screen.dart';
import '../../features/messages/screens/new_message_screen.dart';
import '../../features/messages/providers/messages_provider.dart';
import '../../features/messages/utils/chat_routes.dart';
import '../../features/groups/data/group_models.dart';
import '../../features/groups/screens/group_detail_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/campus_positions/screens/edit_campus_position_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/public_profile_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/scholars/screens/blueprint_bond_screen.dart';
import '../../features/attendance/screens/attendance_scanner_screen.dart';
import '../../features/connections/screens/connections_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/policies/screens/policy_document_screen.dart';
import '../../features/policies/screens/policy_gate_screen.dart';
import '../../shared/widgets/nav_shell.dart';

/// The application's route table.
///
/// Separated from [routerProvider] so it can be inspected without constructing the auth
/// notifier — which needs an initialised Supabase client, and therefore put the shape of the
/// route table out of reach of tests. The shape is load-bearing: whether a route sits inside
/// the navigation shell decides both whether the user sees a bottom navigation bar over it and
/// whether a push from it can lock the navigator.
List<RouteBase> appRoutes() => [
  GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
  GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
  GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
  GoRoute(path: '/forgot-password', builder: (context, state) => const ForgotPasswordScreen()),
  GoRoute(
    path: '/reset-password',
    builder: (context, state) =>
        ResetPasswordScreen(email: state.extra as String?),
  ),
  GoRoute(path: '/verify-email', builder: (context, state) => const VerifyEmailScreen()),
  GoRoute(path: '/suspended', builder: (context, state) => const SuspendedScreen()),
  GoRoute(
    path: '/accept-policies',
    builder: (context, state) => const PolicyGateScreen(),
  ),
  GoRoute(
    path: '/policies/:slug',
    builder: (context, state) =>
        PolicyDocumentScreen(slug: state.pathParameters['slug']!),
  ),
  GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
  GoRoute(
    path: '/users/:profileId',
    builder: (context, state) => PublicProfileScreen(
      profileId: state.pathParameters['profileId']!,
      preloadedName: state.extra as String?,
    ),
  ),
  GoRoute(
    path: '/groups/:groupId',
    builder: (context, state) =>
        GroupDetailScreen(groupId: state.pathParameters['groupId']!),
  ),
  GoRoute(
    path: '/notifications',
    builder: (context, state) => const NotificationsScreen(),
  ),
  // Top-level (not in the shell): a pushed detail screen with its own back button, reachable
  // from anywhere — including the top-level notification center. Keeping it inside the shell
  // made cross-navigator pushes lock the navigator (the '!_debugLocked' crash).
  GoRoute(
    path: '/connections',
    builder: (context, state) => const ConnectionsScreen(),
  ),
  // Same reasoning as '/connections' above: reachable from the top-level notification center
  // (the Blueprint Bond completion nudge), so it cannot live inside the shell. It used to,
  // which surfaced as the app appearing to sign out when tapping that notification — the
  // navigator-lock crash unwound the whole route stack back to '/login'-adjacent state rather
  // than a real session loss.
  GoRoute(
    path: '/profile/blueprint-bond',
    builder: (context, state) => const BlueprintBondScreen(),
  ),
  // Conversations live outside the shell for two reasons. The visible one is report #2: a
  // full-screen chat had the bottom navigation bar under it and its own header over it, two
  // scaffolds deep. The other is stability — chat pushes top-level routes (a group sender's
  // avatar opens '/users/:profileId', the header opens '/groups/:groupId'), and that exact
  // cross-navigator push from inside the shell is what locked the navigator for
  // '/connections' and '/profile/blueprint-bond' above.
  GoRoute(
    // Two segments, so it can never be matched as a DM id by the route below.
    path: '/chat/group/:conversationId',
    builder: (context, state) {
      final args = state.extra as GroupChatArgs?;
      return ChatScreen(
        matchId: state.pathParameters['conversationId']!,
        groupTitle: args?.name ?? 'Group',
        groupId: args?.groupId,
        groupAvatarUrl: args?.avatarUrl,
      );
    },
  ),
  GoRoute(
    path: '/chat/:matchId',
    // `extra` is absent on a cold deep link or a legacy redirect; ChatScreen fetches the
    // thread itself in that case rather than requiring it.
    builder: (context, state) => ChatScreen(
      matchId: state.pathParameters['matchId']!,
      thread: state.extra as MessageThread?,
    ),
  ),
  // Top-level scanner route — opened from push notifications and the Campus Hub card.
  GoRoute(
    path: '/attendance/scan',
    // `?session=` is carried from the push payload so a tap on a stale notification can say
    // *which* session closed instead of a bare "Attendance is closed".
    builder: (context, state) => AttendanceScannerScreen(
      sessionId: state.uri.queryParameters['session'],
    ),
  ),
  ShellRoute(
    builder: (context, state, child) => NavShell(child: child),
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => const CampusHubScreen(),
        routes: [
          GoRoute(
            path: 'updates',
            builder: (context, state) => const CampusUpdatesScreen(),
          ),
          GoRoute(
            path: 'opportunities',
            builder: (context, state) => const CampusOpportunitiesScreen(),
          ),
          GoRoute(
            path: 'resources',
            builder: (context, state) => const CampusResourcesScreen(),
          ),
          GoRoute(
            path: 'my-posts',
            builder: (context, state) => const MyCampusPostsScreen(),
            routes: [
              GoRoute(
                path: 'new',
                // `extra` carries an AuthorCampusPost when editing; null when creating.
                builder: (context, state) => ComposeCampusPostScreen(
                  existing: state.extra as AuthorCampusPost?,
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'posts/:postId',
            builder: (context, state) => CampusPostDetailScreen(
              postId: state.pathParameters['postId']!,
            ),
          ),
          GoRoute(
            path: 'directory',
            builder: (context, state) => const CampusDirectoryScreen(),
            routes: [
              GoRoute(
                path: ':positionId',
                builder: (context, state) => CampusPositionDetailScreen(
                  positionId: state.pathParameters['positionId']!,
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/discover',
        // Groups were the third segment here until report #19 moved them into Messages.
        // `?tab=groups` is still in saved links and in-app references, so it forwards rather
        // than landing on a Discovery screen that no longer has that segment.
        redirect: (context, state) =>
            state.uri.queryParameters['tab'] == 'groups' ? groupsPath : null,
        builder: (context, state) => const DiscoveryScreen(),
      ),
      GoRoute(
        path: '/activities',
        builder: (context, state) => const ActivitiesScreen(),
        routes: [
          GoRoute(
            path: 'create',
            builder: (context, state) => const CreateActivityScreen(),
          ),
          GoRoute(
            path: ':activityId',
            builder: (context, state) => ActivityDetailScreen(
              activity: state.extra as Activity,
            ),
          ),
        ],
      ),
      GoRoute(
        path: messagesPath,
        builder: (context, state) => const MessagesScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const NewMessageScreen(),
          ),
          GoRoute(
            path: 'groups',
            // No transition: this is a segment switch inside one destination, and a page slide
            // would read as having navigated somewhere else. It is still a real route rather
            // than local state, so back behaviour is correct and the location is deep-linkable.
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: GroupsScreen()),
          ),
          // Conversations are NOT here any more — see the top-level '/chat' routes. The two
          // legacy locations below redirect there for one release.
          GoRoute(
            path: 'group/:conversationId',
            redirect: (context, state) =>
                groupChatPath(state.pathParameters['conversationId']!),
          ),
          GoRoute(
            // Must come after every static child above, or it swallows them.
            path: ':matchId',
            redirect: (context, state) => dmChatPath(state.pathParameters['matchId']!),
          ),
        ],
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) => const EditProfileScreen(),
          ),
          GoRoute(
            path: 'campus-position',
            builder: (context, state) => const EditCampusPositionScreen(),
          ),
        ],
      ),
    ],
  ),
    ];
