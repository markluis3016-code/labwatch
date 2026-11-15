import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/errors/app_failure.dart';
import '../data/auth_flow_gate.dart';
import '../data/auth_repository.dart';
import '../domain/auth_validators.dart';
import 'auth_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    AuthFlowGate.instance.begin();
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(_email.text, _password.text);
      // The router redirects once the auth + profile streams settle.
    } on AppFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Try again.');
      }
    } finally {
      AuthFlowGate.instance.end();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to monitor and manage your laboratories.',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: AuthValidators.email,
              ),
              const SizedBox(height: 14),
              PasswordFormField(
                controller: _password,
                label: 'Password',
                validator: (value) =>
                    (value ?? '').isEmpty ? 'Enter your password.' : null,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                AuthErrorBanner(_error!),
              ],
              const SizedBox(height: 20),
              AuthSubmitButton(
                label: 'Sign in',
                busy: _busy,
                onPressed: _busy ? null : _submit,
              ),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed:
                      _busy ? null : () => context.go('/forgot-password'),
                  child: const Text('Forgot password?'),
                ),
              ),
              const Divider(height: 22),
              AuthFooter(
                question: 'New to LabWatch?',
                action: 'Create an account',
                onPressed: _busy ? () {} : () => context.go('/signup'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
