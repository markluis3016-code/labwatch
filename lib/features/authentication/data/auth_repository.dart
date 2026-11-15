import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/errors/app_failure.dart';
import '../../../shared/models/app_user.dart';
import '../../activity/data/activity_repository.dart';

/// Safe, user-facing auth failure. Never contains raw Firebase details.
class AuthFailure extends AppFailure {
  AuthFailure(super.message);
}

/// Client-side login throttle. This is a UX safeguard only; Firebase Auth
/// enforces real rate limiting server-side. Failures persist across restarts.
class LoginThrottle {
  static const _maxAttempts = 5;
  static const _lockout = Duration(minutes: 5);
  static const _kCount = 'login_fail_count';
  static const _kUntil = 'login_locked_until';

  Future<Duration?> remainingLock() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_kUntil);
    if (until == null) return null;
    final left =
        DateTime.fromMillisecondsSinceEpoch(until).difference(DateTime.now());
    if (left <= Duration.zero) {
      await reset();
      return null;
    }
    return left;
  }

  Future<void> recordFailure() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_kCount) ?? 0) + 1;
    await prefs.setInt(_kCount, count);
    if (count >= _maxAttempts) {
      await prefs.setInt(
        _kUntil,
        DateTime.now().add(_lockout).millisecondsSinceEpoch,
      );
    }
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCount);
    await prefs.remove(_kUntil);
  }
}

class AuthRepository {
  AuthRepository(this._auth, this._db, this._throttle, this._activity);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final LoginThrottle _throttle;
  final ActivityRepository _activity;

  /// Use idTokenChanges so the router sees a newly verified email and refreshes
  /// `emailVerified` after the ID token is renewed.
  Stream<User?> get authState => _auth.idTokenChanges();

  User? get currentUser => _auth.currentUser;

  Stream<AppUser?> watchProfile(String uid) => _db
      .doc('users/$uid')
      .snapshots()
      .map((snapshot) => snapshot.exists ? AppUser.fromDoc(snapshot) : null);

  Future<void> signIn(String email, String password) async {
    final lock = await _throttle.remainingLock();
    if (lock != null) {
      final minutes = lock.inMinutes + 1;
      throw AuthFailure('Too many attempts. Try again in $minutes min.');
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await _throttle.reset();
      unawaited(_logLoginIfActive(credential.user));
    } on FirebaseAuthException catch (error) {
      if (_countsAsFailedLoginAttempt(error.code)) {
        await _throttle.recordFailure();
      }
      throw AuthFailure(_signInMessage(error));
    } catch (_) {
      throw AuthFailure('Something went wrong. Try again.');
    }
  }

  /// Creates the Auth account, a pending Instructor profile and sends the
  /// verification email. Public sign-up can never choose a privileged role.
  Future<void> signUp({
    required String fullName,
    required String email,
    required String password,
    required String phone,
  }) async {
    UserCredential? credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw AuthFailure('Could not create your account. Please try again.');
      }

      await user.updateDisplayName(fullName.trim());
      await _db.doc('users/${user.uid}').set(<String, dynamic>{
        'displayName': fullName.trim(),
        'email': user.email ?? email.trim(),
        'phone': phone.trim(),
        'role': UserRole.instructor.name,
        'status': AccountStatus.pending.name,
        'canControlDevices': false,
        'assignedLabIds': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // The account and profile exist even if this fails; the verify screen
      // offers a resend.
      try {
        await user.sendEmailVerification();
      } catch (_) {}
    } on FirebaseAuthException catch (error) {
      await _rollback(credential);
      throw AuthFailure(_signUpMessage(error));
    } on AppFailure {
      await _rollback(credential);
      rethrow;
    } catch (_) {
      await _rollback(credential);
      throw AuthFailure(
        'We could not finish creating your account. Please try again.',
      );
    }
  }

  /// Sends a reset email. Account-existence errors are deliberately reported
  /// as success so the screen cannot be used to enumerate registered emails.
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      switch (error.code) {
        case 'network-request-failed':
          throw AuthFailure(
            'No network connection. Check your connection and try again.',
          );
        case 'too-many-requests':
          throw AuthFailure('Too many requests. Please try again later.');
        case 'operation-not-allowed':
          throw AuthFailure(
            'Password reset is not available. Contact an administrator.',
          );
      }
      // user-not-found / invalid-email: pretend it worked (no enumeration).
    }
  }

  Future<void> sendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw AuthFailure('You are signed out. Please sign in again.');
    }
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (error) {
      switch (error.code) {
        case 'network-request-failed':
          throw AuthFailure(
            'No network connection. Check your connection and try again.',
          );
        case 'too-many-requests':
          throw AuthFailure(
            'Too many emails requested. Please wait a few minutes.',
          );
      }
      throw AuthFailure('Could not send the verification email. Try again.');
    }
  }

  Future<User?> reloadCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      await user.reload();
      // reload() refreshes the user record but may leave the cached ID token
      // with email_verified=false. Firestore rules read the token, so force a
      // refresh before the router lets a newly verified user into the app.
      await _auth.currentUser?.getIdToken(true);
    } on FirebaseAuthException catch (error) {
      if (error.code == 'network-request-failed') {
        throw AuthFailure(
          'No network connection. Check your connection and try again.',
        );
      }
      throw AuthFailure('Could not check your verification status. Try again.');
    }
    return _auth.currentUser;
  }

  Future<void> updateOwnProfile({
    required String displayName,
    required String phone,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw AuthFailure('You are signed out. Please sign in again.');
    }

    try {
      await _db.doc('users/${user.uid}').update(<String, dynamic>{
        'displayName': displayName.trim(),
        'phone': phone.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      throw AuthFailure(
        'Could not save your profile. Check your connection and try again.',
      );
    }

    if (user.displayName != displayName.trim()) {
      try {
        await user.updateDisplayName(displayName.trim());
      } catch (_) {
        // Display name in Firestore is the source of truth for the app.
      }
    }
    unawaited(_activity.log('profile_updated'));
  }

  Future<void> signOut() async {
    await _activity.log('logout');
    await _auth.signOut();
  }

  Future<void> _logLoginIfActive(User? user) async {
    if (user == null || !user.emailVerified) return;
    try {
      final snapshot = await _db.doc('users/${user.uid}').get();
      if (!snapshot.exists) return;
      if (AppUser.fromDoc(snapshot).isActive) {
        await _activity.log('login');
      }
    } catch (_) {
      // Never block sign-in on audit logging.
    }
  }

  Future<void> _rollback(UserCredential? credential) async {
    final user = credential?.user;
    if (user == null) return;
    try {
      await user.delete();
    } catch (_) {
      // If rollback fails, the account is left without a profile and the
      // account-problem screen offers a retry/sign-out path.
    }
  }

  /// Counts credential failures towards the local throttle, but not network,
  /// configuration, disabled-account or rate-limit errors.
  bool _countsAsFailedLoginAttempt(String code) {
    return switch (code) {
      'network-request-failed' ||
      'too-many-requests' ||
      'user-disabled' ||
      'operation-not-allowed' ||
      'configuration-not-found' ||
      'invalid-api-key' ||
      'api-key-not-valid' ||
      'app-not-authorized' ||
      'unauthorized-domain' ||
      'internal-error' =>
        false,
      _ => true,
    };
  }

  String _signInMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'network-request-failed' =>
        'No network connection. Check your connection and try again.',
      'too-many-requests' =>
        'Too many attempts. Please wait a few minutes and try again.',
      'user-disabled' =>
        'This account has been disabled. Contact an administrator.',
      'operation-not-allowed' =>
        'Email/password sign-in is not enabled for this Firebase project. '
            'Contact an administrator.',
      'invalid-email' => 'Enter a valid email address.',
      'user-not-found' => 'No account was found for this email address.',
      'wrong-password' =>
        'Incorrect password. Check your password and try again.',
      'invalid-credential' ||
      'invalid-login-credentials' =>
        'Incorrect email or password. If this is a demo account, make sure '
            'the demo seed script has been run.',
      'configuration-not-found' ||
      'invalid-api-key' ||
      'api-key-not-valid' ||
      'app-not-authorized' ||
      'unauthorized-domain' =>
        'Firebase Authentication is not configured correctly for this app. '
            'Check the Firebase project settings.',
      'internal-error' =>
        'Firebase Authentication is temporarily unavailable. Please try again.',
      _ => 'Sign-in failed (${error.code}). Please try again.',
    };
  }

  String _signUpMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'An account with this email already exists. Try signing in instead.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'network-request-failed':
        return 'No network connection. Check your connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'Email/password sign-up is not enabled. Contact an administrator.';
    }
    return 'Could not create your account. Please try again.';
  }
}

final loginThrottleProvider = Provider<LoginThrottle>((_) => LoginThrottle());

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
    ref.watch(loginThrottleProvider),
    ref.watch(activityRepositoryProvider),
  ),
);

final firebaseUserProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).authState,
);

/// Live profile. An approval/role change by an admin takes effect immediately.
final currentUserProvider = StreamProvider<AppUser?>((ref) {
  final fbUser = ref.watch(firebaseUserProvider).valueOrNull;
  if (fbUser == null) return Stream.value(null);
  return ref.watch(authRepositoryProvider).watchProfile(fbUser.uid);
});
