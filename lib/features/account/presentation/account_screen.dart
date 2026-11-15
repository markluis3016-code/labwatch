import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/account_chips.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../shared/errors/app_failure.dart';
import '../../../shared/models/app_user.dart';
import '../../authentication/data/auth_repository.dart';
import '../../authentication/domain/auth_validators.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _loadedUid;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _sync(AppUser user) {
    if (_loadedUid == user.uid) return;
    _loadedUid = user.uid;
    _name.text = user.displayName;
    _phone.text = user.phone;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).updateOwnProfile(
            displayName: _name.text,
            phone: _phone.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save your profile. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final themeMode = ref.watch(themeModeProvider);
    if (user == null) {
      return const Scaffold(body: LoadingState(label: 'Loading account…'));
    }
    _sync(user);

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: PageBody(
        maxWidth: 860,
        child: ListView(
          children: [
            SectionCard(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 30,
                    child: Text(
                      user.initials,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    user.displayName.isEmpty ? user.email : user.displayName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      RoleChip(user.role),
                      AccountStatusChip(user.status),
                      if (user.createdAt != null)
                        Chip(
                          avatar: const Icon(Icons.calendar_today_outlined, size: 16),
                          label: Text('Joined ${DateFormat.yMMMd().format(user.createdAt!)}'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Profile',
              subtitle:
                  'Only your name and contact number can be edited here. '
                  'Role, status, permissions and lab assignments are managed '
                  'by an administrator.',
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: AuthValidators.fullName,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: const InputDecoration(
                        labelText: 'Contact number',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: AuthValidators.phone,
                      onFieldSubmitted: (_) => _save(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: scheme.error)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : const Icon(Icons.save_outlined, size: 19),
                      label: const Text('Save profile'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Appearance',
              subtitle: 'Saved on this device',
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {
                  themeMode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light,
                },
                onSelectionChanged: (value) =>
                    ref.read(themeModeProvider.notifier).setMode(value.first),
              ),
            ),
            const SizedBox(height: 14),
            _Shortcuts(user: user),
            const SizedBox(height: 14),
            Card(
              child: ListTile(
                leading: Icon(Icons.logout, color: scheme.error),
                title: Text('Sign out', style: TextStyle(color: scheme.error)),
                subtitle: const Text('End this session on this device'),
                onTap: () => ref.read(authRepositoryProvider).signOut(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final items = <_Shortcut>[
      const _Shortcut(Icons.notifications_none_outlined, 'Notifications', 'Reminders and user notifications', '/notifications'),
      const _Shortcut(Icons.history, 'Activity history', 'Recorded actions for your access level', '/activity'),
      const _Shortcut(Icons.assessment_outlined, 'Reports', 'Export laboratory and equipment reports', '/reports'),
    ];

    if (user.isAdmin) {
      items.insertAll(0, const [
        _Shortcut(Icons.manage_accounts_outlined, 'User management', 'Approve, activate and assign roles', '/admin/users'),
        _Shortcut(Icons.science_outlined, 'Laboratories', 'Manage laboratories and monitoring', '/labs'),
        _Shortcut(Icons.settings_outlined, 'System settings', 'Energy threshold and configuration', '/settings'),
      ]);
    } else if (user.isStaff) {
      items.insertAll(0, [
        const _Shortcut(Icons.science_outlined, 'Laboratories', 'Monitor assigned laboratories', '/labs'),
        const _Shortcut(Icons.fact_check_outlined, 'Inspections', 'Before-use and after-use checks', '/inspections'),
        if (user.mayControlDevices)
          const _Shortcut(Icons.power_settings_new, 'Device control', 'Light and AC commands (gateway required)', '/control'),
      ]);
    } else {
      items.insertAll(0, const [
        _Shortcut(Icons.science_outlined, 'Laboratories', 'View laboratory availability and details', '/labs'),
        _Shortcut(Icons.calendar_month_outlined, 'Schedule', 'Reserve laboratories and view bookings', '/schedule'),
        _Shortcut(Icons.fact_check_outlined, 'Inspections', 'Complete equipment checklists', '/inspections'),
      ]);
    }

    return SectionCard(
      title: 'Navigation',
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(items[index].icon),
              title: Text(items[index].title),
              subtitle: Text(items[index].subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(items[index].route),
            ),
            if (index != items.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _Shortcut {
  const _Shortcut(this.icon, this.title, this.subtitle, this.route);

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}
