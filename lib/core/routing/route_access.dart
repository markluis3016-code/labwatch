import '../../shared/models/app_user.dart';

/// Single source of truth for route-level role checks. Firestore rules remain
/// the real data enforcement; this only keeps navigation honest.
class RouteAccess {
  RouteAccess._();

  static bool canAccess(AppUser user, String root) {
    if (!user.isActive || !user.hasKnownRole) return false;

    return switch (root) {
      '/dashboard' ||
      '/alerts' ||
      '/schedule' ||
      '/equipment' ||
      '/more' ||
      '/activity' ||
      '/labs' ||
      '/inspections' ||
      '/notifications' ||
      '/reports' =>
        true,
      '/control' => user.mayControlDevices,
      '/admin' || '/settings' => user.isAdmin,
      _ => true,
    };
  }
}
