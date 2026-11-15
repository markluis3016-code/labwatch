import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/account_chips.dart';
import '../../../shared/models/app_user.dart';
import '../data/auth_repository.dart';
import 'auth_widgets.dart';

/// Shown to signed-in, verified accounts that are still pending approval or
/// have been deactivated. It refreshes live when an admin changes the status.
class PendingApprovalScreen extends ConsumerWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final scheme = Theme.of(context).colorScheme;

    if (user == null) {
      return AuthScaffold(
        title: 'Account unavailable',
        subtitle: 'We could not load your account profile.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthInfoBanner(
              'If this keeps happening, contact an administrator.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.invalidate(currentUserProvider),
              child: const Text('Check again'),
            ),
            TextButton(
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
              child: const Text('Sign out'),
            ),
          ],
        ),
      );
    }

    final pending = user.status == AccountStatus.pending;
    final title = pending ? 'Awaiting approval' : 'Account deactivated';
    final subtitle = pending
        ? 'Your email is verified. An administrator must approve the account '
            'before you can use LabWatch.'
        : 'An administrator has deactivated this account.';

    return AuthScaffold(
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                pending ? Icons.hourglass_top_rounded : Icons.block_outlined,
                size: 34,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            user.displayName.isEmpty ? user.email : user.displayName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            user.email,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              RoleChip(user.role),
              AccountStatusChip(user.status),
            ],
          ),
          if (user.statusNote != null) ...[
            const SizedBox(height: 16),
            AuthInfoBanner(user.statusNote!),
          ],
          const SizedBox(height: 18),
          Text(
            pending
                ? 'Keep this screen open or check back after an administrator '
                    'reviews your registration.'
                : 'Contact an administrator if you believe this is a mistake.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => ref.invalidate(currentUserProvider),
            child: const Text('Check status'),
          ),
          TextButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
