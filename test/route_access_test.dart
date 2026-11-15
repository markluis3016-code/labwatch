import 'package:flutter_test/flutter_test.dart';
import 'package:labwatch/core/routing/route_access.dart';
import 'package:labwatch/shared/models/app_user.dart';

AppUser user({
  UserRole role = UserRole.instructor,
  AccountStatus status = AccountStatus.active,
  bool hasKnownRole = true,
  bool canControlDevices = false,
  List<String> assignedLabIds = const [],
}) {
  return AppUser(
    uid: 'uid-1',
    email: 'user@labwatch.demo',
    displayName: 'Test User',
    role: role,
    status: status,
    hasKnownRole: hasKnownRole,
    canControlDevices: canControlDevices,
    assignedLabIds: assignedLabIds,
  );
}

void main() {
  group('inactive accounts', () {
    for (final status in [AccountStatus.pending, AccountStatus.disabled]) {
      test('${status.name} accounts are denied every route', () {
        final account = user(
          role: UserRole.admin,
          status: status,
          canControlDevices: true,
          assignedLabIds: const ['lab-1'],
        );
        for (final root in const [
          '/dashboard',
          '/alerts',
          '/schedule',
          '/equipment',
          '/more',
          '/activity',
          '/control',
          '/admin',
          '/labs',
          '/settings',
        ]) {
          expect(
            RouteAccess.canAccess(account, root),
            isFalse,
            reason: '${status.name} should not reach $root',
          );
        }
      });
    }
  });

  test('an active account with an unrecognised role is denied everything', () {
    final unknownRole = user(role: UserRole.admin, hasKnownRole: false);
    for (final root in const [
      '/dashboard',
      '/alerts',
      '/schedule',
      '/equipment',
      '/more',
      '/activity',
      '/control',
      '/admin',
      '/labs',
      '/settings',
    ]) {
      expect(RouteAccess.canAccess(unknownRole, root), isFalse);
    }
  });

  group('active instructors', () {
    test('can use shared read-only areas', () {
      final instructor = user();
      for (final root in const [
        '/dashboard',
        '/alerts',
        '/schedule',
        '/equipment',
        '/more',
        '/activity',
      ]) {
        expect(RouteAccess.canAccess(instructor, root), isTrue);
      }
    });

    test('cannot use device control or admin areas', () {
      final instructor = user();
      expect(RouteAccess.canAccess(instructor, '/control'), isFalse);
      expect(RouteAccess.canAccess(instructor, '/admin'), isFalse);
      expect(RouteAccess.canAccess(instructor, '/labs'), isTrue);
      expect(RouteAccess.canAccess(instructor, '/settings'), isFalse);
    });
  });

  group('active staff', () {
    test('can control devices only with the grant and an assigned lab', () {
      expect(
        RouteAccess.canAccess(
          user(
            role: UserRole.staff,
            canControlDevices: true,
            assignedLabIds: const ['lab-1'],
          ),
          '/control',
        ),
        isTrue,
      );
      expect(
        RouteAccess.canAccess(
          user(role: UserRole.staff, canControlDevices: true),
          '/control',
        ),
        isFalse,
      );
      expect(
        RouteAccess.canAccess(
          user(
              role: UserRole.staff,
              canControlDevices: false,
              assignedLabIds: const ['lab-1']),
          '/control',
        ),
        isFalse,
      );
    });

    test('cannot use administrator-only areas', () {
      final staff = user(role: UserRole.staff);
      expect(RouteAccess.canAccess(staff, '/admin'), isFalse);
      expect(RouteAccess.canAccess(staff, '/labs'), isTrue);
      expect(RouteAccess.canAccess(staff, '/settings'), isFalse);
    });
  });

  group('active administrators', () {
    test('can reach every known area', () {
      final admin = user(role: UserRole.admin);
      for (final root in const [
        '/dashboard',
        '/alerts',
        '/schedule',
        '/equipment',
        '/more',
        '/activity',
        '/control',
        '/admin',
        '/labs',
        '/settings',
      ]) {
        expect(RouteAccess.canAccess(admin, root), isTrue);
      }
    });

    test('unknown routes are handled by the router, not denied here', () {
      expect(RouteAccess.canAccess(user(role: UserRole.admin), '/unknown'),
          isTrue);
    });
  });
}
