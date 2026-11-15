import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labwatch/core/theme/app_theme.dart';
import 'package:labwatch/features/authentication/presentation/login_screen.dart';
import 'package:labwatch/features/authentication/presentation/sign_up_screen.dart';

Widget wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      home: child,
    ),
  );
}

void main() {
  testWidgets('login screen renders and validates an empty submit', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Forgot password?'), findsOneWidget);

    await tester.ensureVisible(find.text('Sign in').last);
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();

    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
  });

  testWidgets(
    'sign-up explains the pending Instructor defaults and exposes no role picker',
    (tester) async {
      await tester.pumpWidget(wrap(const SignUpScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Create your account'), findsOneWidget);
      expect(
        find.textContaining('cannot choose an Administrator role'),
        findsOneWidget,
      );
      expect(find.text('Create account'), findsOneWidget);

      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your full name.'), findsOneWidget);
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(find.text('Enter your contact number.'), findsOneWidget);
      expect(find.text('Enter a password.'), findsOneWidget);
      expect(find.text('Confirm your password.'), findsOneWidget);
    },
  );
}
