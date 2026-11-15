import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/account_chips.dart';
import '../../../shared/errors/app_failure.dart';
import '../../../shared/models/app_user.dart';
import '../../authentication/data/auth_repository.dart';
import '../data/user_admin_repository.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() =>
      _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  final _search = TextEditingController();
  String _query = '';
  _StatusFilter _status = _StatusFilter.all;
  UserRole? _role;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AppUser> _filtered(List<AppUser> users) {
    final query = _query.trim().toLowerCase();
    final result = users.where((user) {
      final matchesQuery = query.isEmpty ||
          user.displayName.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query);
      final matchesStatus = switch (_status) {
        _StatusFilter.all => true,
        _StatusFilter.pending => user.status == AccountStatus.pending,
        _StatusFilter.active => user.status == AccountStatus.active,
        _StatusFilter.disabled => user.status == AccountStatus.disabled,
      };
      final matchesRole = _role == null || user.role == _role;
      return matchesQuery && matchesStatus && matchesRole;
    }).toList();

    result.sort((a, b) {
      if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
      final aName = a.displayName.isEmpty ? a.email : a.displayName;
      final bName = b.displayName.isEmpty ? b.email : b.displayName;
      return aName.toLowerCase().compareTo(bName.toLowerCase());
    });
    return result;
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    } on AppFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Something went wrong. Try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<UserRole?> _pickRole({
    required AppUser user,
    required String title,
    required String action,
  }) async {
    var selected =
        user.role == UserRole.staff ? UserRole.staff : UserRole.instructor;
    final displayName =
        user.displayName.isEmpty ? user.email : user.displayName;

    return showDialog<UserRole>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose the role for $displayName.'),
                const SizedBox(height: 14),
                DropdownButtonFormField<UserRole>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [
                    for (final role in [UserRole.staff, UserRole.instructor])
                      DropdownMenuItem(
                        value: role,
                        child: Text(role.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selected = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'The user must also verify their email before they can sign in. '
                  'Administrator accounts are created with the Admin SDK, not here.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(selected),
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<void> _approve(AppUser user) async {
    final role = await _pickRole(
      user: user,
      title: 'Approve account',
      action: 'Approve',
    );
    if (role == null || !mounted) return;
    await _run(
      () => ref
          .read(userAdminRepositoryProvider)
          .approve(user.uid, role, targetLabel: user.email),
      'Account approved.',
    );
  }

  Future<void> _reject(AppUser user) async {
    final confirmed = await _confirm(
      title: 'Reject registration',
      message:
          'The account will be disabled and cannot access LabWatch. The Firebase '
          'Auth user remains; only the Admin SDK can delete it.',
      action: 'Reject',
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref
          .read(userAdminRepositoryProvider)
          .reject(user.uid, targetLabel: user.email),
      'Registration rejected.',
    );
  }

  Future<void> _setStatus(AppUser user, AccountStatus status) async {
    if (status == AccountStatus.disabled) {
      final confirmed = await _confirm(
        title: 'Deactivate account',
        message:
            'The user will lose access to protected features immediately and '
            'cannot use LabWatch again until reactivated.',
        action: 'Deactivate',
      );
      if (confirmed != true || !mounted) return;
    }
    await _run(
      () => ref
          .read(userAdminRepositoryProvider)
          .setStatus(user.uid, status, targetLabel: user.email),
      status == AccountStatus.active
          ? 'Account activated.'
          : 'Account deactivated.',
    );
  }

  Future<void> _changeRole(AppUser user) async {
    final role = await _pickRole(
      user: user,
      title: 'Change role',
      action: 'Save',
    );
    if (role == null || !mounted || role == user.role) return;
    await _run(
      () => ref
          .read(userAdminRepositoryProvider)
          .setRole(user.uid, role, targetLabel: user.email),
      'Role updated.',
    );
  }

  Future<void> _editLabs(AppUser user) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _LabAssignmentsDialog(initial: user.assignedLabIds),
    );
    if (result == null || !mounted) return;

    final ids = result
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    await _run(
      () => ref
          .read(userAdminRepositoryProvider)
          .setAssignedLabs(user.uid, ids, targetLabel: user.email),
      'Lab assignments saved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('User management')),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _errorState(),
        data: (users) {
          final filtered = _filtered(users);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(allUsersProvider),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _Stats(users: users),
                const SizedBox(height: 16),
                _filters(),
                const SizedBox(height: 14),
                Text(
                  '${filtered.length} of ${users.length} accounts',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                if (filtered.isEmpty)
                  _emptyState()
                else
                  for (final user in filtered)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _UserCard(
                        user: user,
                        isSelf: me?.uid == user.uid,
                        canManage: me != null &&
                            me.uid != user.uid &&
                            (!user.isAdmin || user.isPending),
                        onApprove: () => _approve(user),
                        onReject: () => _reject(user),
                        onActivate: () =>
                            _setStatus(user, AccountStatus.active),
                        onDeactivate: () =>
                            _setStatus(user, AccountStatus.disabled),
                        onChangeRole: () => _changeRole(user),
                        onEditLabs: () => _editLabs(user),
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Search by name or email',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in _StatusFilter.values)
              ChoiceChip(
                label: Text(filter.label),
                selected: _status == filter,
                onSelected: (selected) {
                  if (selected) setState(() => _status = filter);
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Role',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<UserRole?>(
              value: _role,
              isExpanded: true,
              items: [
                const DropdownMenuItem<UserRole?>(
                  value: null,
                  child: Text('All roles'),
                ),
                for (final role in UserRole.values)
                  DropdownMenuItem<UserRole?>(
                    value: role,
                    child: Text(role.label),
                  ),
              ],
              onChanged: (value) => setState(() => _role = value),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Icon(Icons.manage_search, size: 42),
            const SizedBox(height: 10),
            Text(
              'No accounts match these filters.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Try clearing the search or choosing a different status.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44),
            const SizedBox(height: 10),
            Text(
              'Could not load users.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Check your connection and administrator permissions.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.invalidate(allUsersProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _StatusFilter {
  all,
  pending,
  active,
  disabled;

  String get label => switch (this) {
        _StatusFilter.all => 'All',
        _StatusFilter.pending => 'Pending',
        _StatusFilter.active => 'Active',
        _StatusFilter.disabled => 'Disabled',
      };
}

class _Stats extends StatelessWidget {
  const _Stats({required this.users});

  final List<AppUser> users;

  @override
  Widget build(BuildContext context) {
    final pending = users.where((user) => user.isPending).length;
    final active = users.where((user) => user.isActive).length;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Total',
            value: users.length.toString(),
            icon: Icons.people_outline,
            color: AppColors.royal,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: 'Pending',
            value: pending.toString(),
            icon: Icons.hourglass_top_rounded,
            color: AppColors.warning,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatCard(
            label: 'Active',
            value: active.toString(),
            icon: Icons.check_circle_outline,
            color: AppColors.success,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.isSelf,
    required this.canManage,
    required this.onApprove,
    required this.onReject,
    required this.onActivate,
    required this.onDeactivate,
    required this.onChangeRole,
    required this.onEditLabs,
  });

  final AppUser user;
  final bool isSelf;
  final bool canManage;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;
  final VoidCallback onChangeRole;
  final VoidCallback onEditLabs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = user.displayName.isEmpty ? user.email : user.displayName;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  child: Text(
                    user.initials,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                RoleChip(user.role),
                AccountStatusChip(user.status),
                if (isSelf) const _TagChip('You'),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                if (user.phone.isNotEmpty)
                  _Meta(icon: Icons.phone_outlined, text: user.phone),
                _Meta(
                  icon: Icons.science_outlined,
                  text: user.assignedLabIds.isEmpty
                      ? 'No labs assigned'
                      : user.assignedLabIds.join(', '),
                ),
                if (user.createdAt != null)
                  _Meta(
                    icon: Icons.calendar_today_outlined,
                    text: DateFormat.yMMMd().format(user.createdAt!),
                  ),
              ],
            ),
            if (user.statusNote != null) ...[
              const SizedBox(height: 8),
              Text(
                user.statusNote!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (canManage) ...[
              const SizedBox(height: 12),
              _actions(),
            ] else if (isSelf) ...[
              const SizedBox(height: 10),
              Text(
                'This is your account. Use the Account tab to edit your profile.',
                style: theme.textTheme.bodySmall,
              ),
            ] else if (user.isAdmin) ...[
              const SizedBox(height: 10),
              Text(
                'Administrator accounts are managed with the Admin SDK.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actions() {
    if (user.isPending) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: onApprove,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Approve'),
          ),
          OutlinedButton.icon(
            onPressed: onReject,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Reject'),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (user.isActive)
          OutlinedButton.icon(
            onPressed: onDeactivate,
            icon: const Icon(Icons.block_outlined, size: 18),
            label: const Text('Deactivate'),
          )
        else
          FilledButton.icon(
            onPressed: onActivate,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Activate'),
          ),
        TextButton.icon(
          onPressed: onChangeRole,
          icon: const Icon(Icons.badge_outlined, size: 18),
          label: const Text('Change role'),
        ),
        TextButton.icon(
          onPressed: onEditLabs,
          icon: const Icon(Icons.science_outlined, size: 18),
          label: const Text('Labs'),
        ),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Owns its controller so the text field stays valid for the dialog's exit
/// animation instead of being disposed as soon as `showDialog` returns.
class _LabAssignmentsDialog extends StatefulWidget {
  const _LabAssignmentsDialog({required this.initial});

  final List<String> initial;

  @override
  State<_LabAssignmentsDialog> createState() => _LabAssignmentsDialogState();
}

class _LabAssignmentsDialogState extends State<_LabAssignmentsDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial.join(', '));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Lab assignments'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Comma-separated lab IDs. Staff device control requires the lab '
              'to be listed here as well as the control permission.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Lab IDs',
                hintText: 'lab-1, lab-2',
              ),
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
