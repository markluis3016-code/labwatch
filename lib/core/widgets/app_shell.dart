import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/alerts/data/energy_watcher.dart';
import '../../features/authentication/data/auth_repository.dart';
import '../../features/notifications/data/notification_repository.dart';
import '../../shared/models/app_user.dart';
import '../theme/app_theme.dart';
import 'labwatch_logo.dart';
import 'ui_kit.dart';

/// Responsive application shell:
/// - Desktop/tablet (wide): collapsible sidebar with organized sections.
/// - Mobile: navigation drawer for full access and a compact top app bar.
/// Preserves existing routes and role-based navigation permissions.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final unread = ref.watch(unreadNotificationCountProvider);
    final items = _itemsFor(user);
    final sections = _sectionsFor(items);
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _selectedIndex(items, location);
    final currentItem =
        selectedIndex >= 0 ? items[selectedIndex] : items.firstOrNull;

    void navigate(_NavItem item) {
      if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
        Navigator.of(context).pop();
      }
      context.go(item.path);
    }

    Future<void> signOut() async {
      final ok = await confirmAction(
        context,
        title: 'Sign out',
        message: 'End this session on this device?',
        confirmLabel: 'Sign out',
      );
      if (!ok) return;
      await ref.read(authRepositoryProvider).signOut();
    }

    return EnergyWatchRunner(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          final compactRail = constraints.maxWidth >= 960 && _collapsed;

          if (wide) {
            return Scaffold(
              body: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    width: compactRail ? 84 : 272,
                    child: _NavPanel(
                      user: user,
                      sections: sections,
                      selectedPath: currentItem?.path,
                      unread: unread,
                      collapsed: compactRail,
                      onNavigate: navigate,
                      onToggleCollapse: () =>
                          setState(() => _collapsed = !_collapsed),
                      onSignOut: signOut,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: KeyedSubtree(
                        key: ValueKey(location),
                        child: widget.child,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(
              titleSpacing: 4,
              title: Row(
                children: [
                  const LabWatchMark(size: 28, rounded: true),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      currentItem?.label ?? 'LabWatch',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: [
                _NotificationsAction(
                  unread: unread,
                  onTap: () => context.go('/notifications'),
                ),
                IconButton(
                  tooltip: 'Account',
                  onPressed: () => context.go('/more'),
                  icon: const Icon(Icons.person_outline),
                ),
              ],
            ),
            drawer: Drawer(
              width: 320,
              child: SafeArea(
                child: _NavPanel(
                  user: user,
                  sections: sections,
                  selectedPath: currentItem?.path,
                  unread: unread,
                  collapsed: false,
                  inDrawer: true,
                  onNavigate: (item) {
                    Navigator.of(context).pop();
                    context.go(item.path);
                  },
                  onSignOut: () async {
                    Navigator.of(context).pop();
                    await signOut();
                  },
                ),
              ),
            ),
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(
                key: ValueKey(location),
                child: widget.child,
              ),
            ),
          );
        },
      ),
    );
  }

  static List<_NavItem> _itemsFor(AppUser? user) {
    if (user?.isAdmin == true) {
      return const [
        _dashboard,
        _labs,
        _alerts,
        _schedule,
        _equipment,
        _inspections,
        _activity,
        _reports,
        _users,
        _settings,
        _notifications,
        _more,
      ];
    }
    if (user?.isInstructor == true) {
      return const [
        _dashboard,
        _labs,
        _schedule,
        _equipment,
        _inspections,
        _alerts,
        _activity,
        _reports,
        _notifications,
        _more,
      ];
    }
    final items = <_NavItem>[
      _dashboard,
      _labs,
      _alerts,
      _schedule,
      _equipment,
      _inspections,
    ];
    if (user?.mayControlDevices == true) items.add(_control);
    items.addAll(const [_activity, _reports, _notifications, _more]);
    return items;
  }

  static List<_NavSection> _sectionsFor(List<_NavItem> items) {
    _NavItem? pick(String path) {
      for (final item in items) {
        if (item.path == path) return item;
      }
      return null;
    }

    final sectionDefs = <(String, List<String>)>[
      ('Overview', ['/dashboard']),
      ('Operations', ['/labs', '/schedule', '/equipment', '/inspections', '/control']),
      ('Monitoring', ['/alerts', '/notifications', '/activity']),
      ('Insights', ['/reports']),
      ('Administration', ['/admin/users', '/settings']),
      ('Account', ['/more']),
    ];

    final sections = <_NavSection>[];
    for (final def in sectionDefs) {
      final resolved = [
        for (final path in def.$2)
          if (pick(path) != null) pick(path)!,
      ];
      if (resolved.isNotEmpty) {
        sections.add(_NavSection(def.$1, resolved));
      }
    }
    return sections;
  }

  static int _selectedIndex(List<_NavItem> items, String location) {
    var best = -1;
    var bestLength = -1;
    for (var i = 0; i < items.length; i++) {
      final path = items[i].path;
      final matches = location == path || location.startsWith('$path/');
      if (matches && path.length > bestLength) {
        best = i;
        bestLength = path.length;
      }
    }
    return best >= 0 ? best : 0;
  }
}

class _NotificationsAction extends StatelessWidget {
  const _NotificationsAction({required this.unread, required this.onTap});
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = IconButton(
      tooltip: 'Notifications',
      onPressed: onTap,
      icon: const Icon(Icons.notifications_none_outlined),
    );
    if (unread <= 0) return icon;
    return Badge(
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: icon,
    );
  }
}

class _NavPanel extends StatelessWidget {
  const _NavPanel({
    required this.user,
    required this.sections,
    required this.selectedPath,
    required this.unread,
    required this.collapsed,
    required this.onNavigate,
    required this.onSignOut,
    this.onToggleCollapse,
    this.inDrawer = false,
  });

  final AppUser? user;
  final List<_NavSection> sections;
  final String? selectedPath;
  final int unread;
  final bool collapsed;
  final bool inDrawer;
  final ValueChanged<_NavItem> onNavigate;
  final VoidCallback? onToggleCollapse;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              collapsed ? 12 : 14,
              14,
              collapsed ? 12 : 8,
              10,
            ),
            child: Row(
              children: [
                if (collapsed)
                  const Expanded(
                    child: Center(child: LabWatchMark(size: 34)),
                  )
                else
                  const Expanded(
                    child: LabWatchLogo(markSize: 34, compact: true),
                  ),
                if (!collapsed && onToggleCollapse != null)
                  IconButton(
                    tooltip: 'Collapse sidebar',
                    onPressed: onToggleCollapse,
                    icon: const Icon(Icons.chevron_left),
                  ),
              ],
            ),
          ),
          if (collapsed && onToggleCollapse != null)
            IconButton(
              tooltip: 'Expand sidebar',
              onPressed: onToggleCollapse,
              icon: const Icon(Icons.chevron_right),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 8 : 10,
                vertical: 10,
              ),
              children: [
                for (final section in sections) ...[
                  if (!collapsed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                      child: Text(
                        section.title.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  for (final item in section.items)
                    _NavTile(
                      item: item,
                      selected: item.path == selectedPath,
                      collapsed: collapsed,
                      unread: unread,
                      onTap: () => onNavigate(item),
                    ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          _ProfileFooter(
            user: user,
            collapsed: collapsed,
            onSignOut: onSignOut,
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.unread,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final bool collapsed;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = Icon(
      selected ? item.selectedIcon : item.icon,
      color: item.path == '/alerts'
          ? (selected ? AppColors.warning : AppColors.warning)
          : null,
    );
    final showBadge = item.path == '/notifications' && unread > 0;
    final leading = showBadge
        ? Badge(label: Text(unread > 99 ? '99+' : '$unread'), child: icon)
        : icon;

    final bg = selected
        ? scheme.primary.withValues(alpha: 0.12)
        : Colors.transparent;
    final border = selected
        ? Border.all(color: scheme.primary.withValues(alpha: 0.35))
        : null;

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Tooltip(
          message: item.label,
          waitDuration: const Duration(milliseconds: 400),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 44,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: border,
              ),
              child: IconTheme(
                data: IconThemeData(
                  color: item.path == '/alerts'
                      ? (selected
                          ? AppColors.warning
                          : AppColors.warning.withValues(alpha: 0.85))
                      : (selected ? scheme.primary : scheme.onSurfaceVariant),
                ),
                child: Center(child: leading),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: border,
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              IconTheme(
                data: IconThemeData(
                  color: item.path == '/alerts'
                      ? (selected
                          ? AppColors.warning
                          : AppColors.warning.withValues(alpha: 0.85))
                      : (selected ? scheme.primary : scheme.onSurfaceVariant),
                ),
                child: leading,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: item.path == '/alerts'
                            ? (selected ? AppColors.warning : scheme.onSurface)
                            : (selected ? scheme.primary : scheme.onSurface),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileFooter extends StatelessWidget {
  const _ProfileFooter({
    required this.user,
    required this.collapsed,
    required this.onSignOut,
  });

  final AppUser? user;
  final bool collapsed;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = user?.displayName.isNotEmpty == true
        ? user!.displayName
        : (user?.email ?? 'LabWatch');
    final role = user?.role.label ?? '';
    final initials = user?.initials ?? '?';

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Tooltip(
              message: '$name\n$role',
              child: CircleAvatar(
                radius: 17,
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
                child: Text(
                  initials,
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            IconButton(
              tooltip: 'Sign out',
              onPressed: () => onSignOut(),
              icon: Icon(Icons.logout, color: scheme.error),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: scheme.primary.withValues(alpha: 0.12),
            child: Text(
              initials,
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => onSignOut(),
            icon: Icon(Icons.logout_rounded, color: scheme.error),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.path, this.icon, this.selectedIcon, this.label);

  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _NavSection {
  const _NavSection(this.title, this.items);
  final String title;
  final List<_NavItem> items;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

const _dashboard = _NavItem(
  '/dashboard',
  Icons.dashboard_outlined,
  Icons.dashboard_rounded,
  'Dashboard',
);
const _labs = _NavItem(
  '/labs',
  Icons.science_outlined,
  Icons.science_rounded,
  'Laboratories',
);
const _alerts = _NavItem(
  '/alerts',
  Icons.warning_amber_outlined,
  Icons.warning_amber_rounded,
  'Alerts',
);
const _schedule = _NavItem(
  '/schedule',
  Icons.calendar_month_outlined,
  Icons.calendar_month_rounded,
  'Schedule',
);
const _equipment = _NavItem(
  '/equipment',
  Icons.inventory_2_outlined,
  Icons.inventory_2_rounded,
  'Equipment',
);
const _inspections = _NavItem(
  '/inspections',
  Icons.fact_check_outlined,
  Icons.fact_check_rounded,
  'Inspections',
);
const _activity = _NavItem(
  '/activity',
  Icons.history_rounded,
  Icons.history_rounded,
  'Activity',
);
const _reports = _NavItem(
  '/reports',
  Icons.assessment_outlined,
  Icons.assessment_rounded,
  'Reports',
);
const _users = _NavItem(
  '/admin/users',
  Icons.manage_accounts_outlined,
  Icons.manage_accounts_rounded,
  'User management',
);
const _settings = _NavItem(
  '/settings',
  Icons.settings_outlined,
  Icons.settings_rounded,
  'Settings',
);
const _notifications = _NavItem(
  '/notifications',
  Icons.notifications_none_outlined,
  Icons.notifications_rounded,
  'Notifications',
);
const _control = _NavItem(
  '/control',
  Icons.tune_outlined,
  Icons.tune_rounded,
  'Device control',
);
const _more = _NavItem(
  '/more',
  Icons.person_outline,
  Icons.person_rounded,
  'Account',
);
