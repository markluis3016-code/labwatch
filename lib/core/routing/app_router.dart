import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/presentation/account_screen.dart';
import '../../features/activity/presentation/activity_screen.dart';
import '../../features/admin/presentation/user_management_screen.dart';
import '../../features/alerts/presentation/alerts_screen.dart';
import '../../features/authentication/data/auth_flow_gate.dart';
import '../../features/authentication/data/auth_repository.dart';
import '../../features/authentication/presentation/account_problem_screen.dart';
import '../../features/authentication/presentation/forgot_password_screen.dart';
import '../../features/authentication/presentation/login_screen.dart';
import '../../features/authentication/presentation/pending_approval_screen.dart';
import '../../features/authentication/presentation/sign_up_screen.dart';
import '../../features/authentication/presentation/splash_screen.dart';
import '../../features/authentication/presentation/verify_email_screen.dart';
import '../../features/control/presentation/device_control_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/equipment/presentation/equipment_screen.dart';
import '../../features/inspections/presentation/inspections_screen.dart';
import '../../features/labs/presentation/lab_detail_screen.dart';
import '../../features/labs/presentation/labs_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/scheduling/presentation/schedule_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../shared/models/inspection.dart';
import '../widgets/app_shell.dart';
import 'route_access.dart';

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(firebaseUserProvider, (_, __) => notifyListeners());
    ref.listen(currentUserProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authChanges = _AuthListenable(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable:
        Listenable.merge([authChanges, AuthFlowGate.instance.busy]),
    redirect: (context, state) => _redirect(ref, state),
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No page matches ${state.uri}.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignUpScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (_, __) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: '/pending',
        builder: (_, __) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: '/account-problem',
        builder: (_, __) => const AccountProblemScreen(),
      ),
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/labs',
            builder: (_, __) => const LabsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) =>
                    LabDetailScreen(labId: state.pathParameters['id'] ?? ''),
              ),
            ],
          ),
          GoRoute(
            path: '/alerts',
            builder: (_, __) => const AlertsScreen(),
          ),
          GoRoute(
            path: '/schedule',
            builder: (_, state) => ScheduleScreen(
              preselectedLabId: state.uri.queryParameters['lab'],
            ),
          ),
          GoRoute(
            path: '/equipment',
            builder: (_, state) => EquipmentScreen(
              labFilter: state.uri.queryParameters['lab'],
            ),
          ),
          GoRoute(
            path: '/inspections',
            builder: (_, state) => InspectionsScreen(
              labFilter: state.uri.queryParameters['lab'],
            ),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, state) {
                  final typeParam = state.uri.queryParameters['type'];
                  return InspectionFormScreen(
                    initialLabId: state.uri.queryParameters['lab'],
                    initialType: typeParam == 'after'
                        ? InspectionType.after
                        : typeParam == 'before'
                            ? InspectionType.before
                            : null,
                    reservationId: state.uri.queryParameters['reservation'],
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/control',
            builder: (_, state) => DeviceControlScreen(
              initialLabId: state.uri.queryParameters['lab'],
            ),
          ),
          GoRoute(
            path: '/activity',
            builder: (_, __) => const ActivityScreen(),
          ),
          GoRoute(
            path: '/reports',
            builder: (_, __) => const ReportsScreen(),
          ),
          GoRoute(
            path: '/more',
            builder: (_, __) => const AccountScreen(),
          ),
          GoRoute(path: '/admin', redirect: (_, __) => '/admin/users'),
          GoRoute(
            path: '/admin/users',
            builder: (_, __) => const UserManagementScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

String? _redirect(Ref ref, GoRouterState state) {
  // A sign-up is in progress: do not react to the transient "auth user exists
  // but profile document has not been written yet" state.
  if (AuthFlowGate.instance.busy.value) return null;

  final location = state.matchedLocation;
  const publicRoutes = {'/login', '/signup', '/forgot-password'};

  final firebaseUser = ref.read(firebaseUserProvider);
  if (firebaseUser.isLoading) return null;

  final fbUser = firebaseUser.valueOrNull;
  if (fbUser == null) {
    return publicRoutes.contains(location) ? null : '/login';
  }

  final profile = ref.read(currentUserProvider);
  if (profile.isLoading) return null;

  if (profile.hasError) {
    return location == '/account-problem' ? null : '/account-problem';
  }

  final user = profile.valueOrNull;
  if (user == null) {
    if (!fbUser.emailVerified) {
      return location == '/verify-email' ? null : '/verify-email';
    }
    return location == '/account-problem' ? null : '/account-problem';
  }

  if (!fbUser.emailVerified) {
    return location == '/verify-email' ? null : '/verify-email';
  }

  if (!user.isActive) {
    return location == '/pending' ? null : '/pending';
  }

  // A profile with a missing or unrecognised role is not a valid account.
  // Send it to the recovery screen instead of guessing a dashboard.
  if (!user.hasKnownRole) {
    return location == '/account-problem' ? null : '/account-problem';
  }

  const resolvedRoutes = {
    '/splash',
    '/login',
    '/signup',
    '/forgot-password',
    '/verify-email',
    '/pending',
    '/account-problem',
  };
  if (resolvedRoutes.contains(location)) return '/dashboard';

  final segments = location.split('/').where((part) => part.isNotEmpty).toList();
  final root = '/${segments.isEmpty ? '' : segments.first}';
  if (!RouteAccess.canAccess(user, root)) return '/dashboard';
  return null;
}
