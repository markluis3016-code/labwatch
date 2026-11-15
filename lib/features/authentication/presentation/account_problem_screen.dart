import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import 'auth_widgets.dart';

/// Signed-in and verified, but the Firestore profile document is missing or
/// unreadable. This is a recovery screen, never a way into the app.
class AccountProblemScreen extends ConsumerWidget {
  const AccountProblemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fbUser = ref.watch(firebaseUserProvider).valueOrNull;
    final profile = ref.watch(currentUserProvider).valueOrNull;
    final roleProblem = profile != null && !profile.hasKnownRole;

    return AuthScaffold(
      title: roleProblem
          ? 'Account role not recognised'
          : 'Account setup incomplete',
      subtitle: roleProblem
          ? 'Your profile exists, but its role is missing or invalid.'
          : 'Your sign-in worked, but your LabWatch profile could not be '
              'loaded.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthInfoBanner(
            roleProblem
                ? 'An administrator must correct the role field on your user '
                    'profile. Valid roles are admin, staff or instructor.'
                : 'This usually means the account profile is missing, or the '
                    'Firestore rules blocked the read. Contact an administrator '
                    'with the details below.',
          ),
          const SizedBox(height: 16),
          if (fbUser != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Signed in as',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(fbUser.email ?? '(no email)'),
                    const SizedBox(height: 2),
                    SelectableText(
                      'UID: ${fbUser.uid}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () {
              ref.invalidate(firebaseUserProvider);
              ref.invalidate(currentUserProvider);
            },
            child: const Text('Retry'),
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
