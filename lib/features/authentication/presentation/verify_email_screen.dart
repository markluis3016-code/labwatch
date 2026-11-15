import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/errors/app_failure.dart';
import '../data/auth_repository.dart';
import 'auth_widgets.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  Timer? _timer;
  int _cooldown = 0;
  bool _checking = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    final repository = ref.read(authRepositoryProvider);
    try {
      await repository.reloadCurrentUser();
      if (!mounted) return;
      ref.invalidate(firebaseUserProvider);

      final verified = repository.currentUser?.emailVerified ?? false;
      if (!verified && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Not verified yet. Open the link in your inbox, then try again.',
            ),
          ),
        );
      }
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not check your email. Try again.');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendVerificationEmail();
      if (!mounted) return;
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email sent.')),
      );
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not send the email. Try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldown <= 1) {
        timer.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final email =
        ref.watch(firebaseUserProvider).valueOrNull?.email ?? 'your email';

    return AuthScaffold(
      title: 'Verify your email',
      subtitle: 'One quick step before your account can be reviewed.',
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
                Icons.mark_email_unread_outlined,
                size: 34,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'We sent a verification link to $email.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Open the link in your inbox, then return here. After your email '
            'is verified, an administrator still needs to approve the account.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            AuthErrorBanner(_error!),
          ],
          const SizedBox(height: 22),
          AuthSubmitButton(
            label: "I've verified my email",
            busy: _checking,
            onPressed: _checking ? null : _check,
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _sending || _cooldown > 0 ? null : _resend,
            child: Text(
              _cooldown > 0
                  ? 'Resend in ${_cooldown}s'
                  : 'Resend verification email',
            ),
          ),
          const Divider(height: 24),
          TextButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
