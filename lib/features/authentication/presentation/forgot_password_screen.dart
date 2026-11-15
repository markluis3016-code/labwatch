import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/errors/app_failure.dart';
import '../data/auth_repository.dart';
import '../domain/auth_validators.dart';
import 'auth_widgets.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _sentEmail;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final email = _email.text.trim();
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sentEmail = email;
      });
    } on AppFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Reset your password',
      subtitle: 'Enter the email address for your account and we will send a '
          'password reset link.',
      child: _sent ? _success(context) : _form(context),
    );
  }

  Widget _success(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthSuccessBanner(
          'If an account exists for ${_sentEmail ?? 'that address'}, a reset '
          'email has been sent. Check your inbox and spam folder.',
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('Back to sign in'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _sent = false;
                    _error = null;
                  }),
          child: const Text('Use a different email'),
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: AuthValidators.email,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            AuthErrorBanner(_error!),
          ],
          const SizedBox(height: 20),
          AuthSubmitButton(
            label: 'Send reset email',
            busy: _busy,
            onPressed: _busy ? null : _submit,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => context.go('/login'),
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    );
  }
}
