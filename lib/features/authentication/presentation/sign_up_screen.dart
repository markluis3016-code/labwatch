import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/errors/app_failure.dart';
import '../data/auth_flow_gate.dart';
import '../data/auth_repository.dart';
import '../domain/auth_validators.dart';
import 'auth_widgets.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
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
      await ref.read(authRepositoryProvider).signUp(
            fullName: _name.text,
            email: _email.text,
            password: _password.text,
            phone: _phone.text,
          );
      // The router sends the new account to the verify-email screen.
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
      title: 'Create your account',
      subtitle:
          'Register with your email. An administrator must approve the account '
          'before it can be used.',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthInfoBanner(
                'New accounts are created as Instructor with Pending status. '
                'You cannot choose an Administrator role; an existing '
                'administrator assigns Staff or Instructor access after approval.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: AuthValidators.fullName,
              ),
              const SizedBox(height: 14),
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
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Contact number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: AuthValidators.phone,
              ),
              const SizedBox(height: 14),
              PasswordFormField(
                controller: _password,
                label: 'Password',
                autofillHints: const [AutofillHints.newPassword],
                helperText:
                    'At least 8 characters, with upper case, lower case and a number.',
                validator: AuthValidators.password,
              ),
              const SizedBox(height: 14),
              PasswordFormField(
                controller: _confirm,
                label: 'Confirm password',
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (value) =>
                    AuthValidators.confirmPassword(value, _password.text),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                AuthErrorBanner(_error!),
              ],
              const SizedBox(height: 20),
              AuthSubmitButton(
                label: 'Create account',
                busy: _busy,
                onPressed: _busy ? null : _submit,
              ),
              const SizedBox(height: 8),
              AuthFooter(
                question: 'Already have an account?',
                action: 'Sign in',
                onPressed: _busy ? () {} : () => context.go('/login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
