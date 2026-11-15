import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_failure.dart';

class LoadFailureView {
  const LoadFailureView({
    required this.title,
    required this.message,
    this.icon = Icons.cloud_off_outlined,
  });

  final String title;
  final String message;
  final IconData icon;
}

/// Maps Firestore/network exceptions to safe, user-facing failures for actions.
/// Never leaks project ids, document paths or stack traces to the UI.
AppFailure mapFirestoreError(
  Object error, {
  String fallback =
      'Could not complete the request. Check your connection and try again.',
}) {
  if (error is AppFailure) return error;
  final view = describeFirestoreLoadError(error, resource: 'information');
  return AppFailure(view.message);
}

/// Classifies a failed data load so list screens can show a specific,
/// actionable message instead of a generic "check connection/permissions" error.
LoadFailureView describeFirestoreLoadError(
  Object error, {
  required String resource,
}) {
  _debugLog(error);

  if (error is FirebaseException) {
    final raw = '${error.code} ${error.message ?? ''}'.toLowerCase();
    switch (error.code) {
      case 'permission-denied':
        return LoadFailureView(
          title: "You don't have permission",
          message:
              "You don't have permission to access $resource. "
              'Sign in with an authorised account or contact an administrator.',
          icon: Icons.lock_outline,
        );
      case 'unauthenticated':
        return const LoadFailureView(
          title: 'Session expired',
          message:
              'Your sign-in session has expired. Please sign out and sign in '
              'again, then retry.',
          icon: Icons.login,
        );
      case 'failed-precondition':
        final missingIndex =
            raw.contains('index') || raw.contains('requires an index');
        return LoadFailureView(
          title: missingIndex
              ? 'Database configuration incomplete'
              : 'Request cannot be completed',
          message: missingIndex
              ? 'Database configuration is incomplete. Please contact the '
                  'administrator to deploy the required Firestore indexes.'
              : 'The request could not be completed because the data or '
                  'database state is not ready. Please try again later.',
          icon: Icons.build_circle_outlined,
        );
      case 'unavailable':
      case 'deadline-exceeded':
      case 'network-request-failed':
        return const LoadFailureView(
          title: 'Unable to connect',
          message:
              'Unable to connect. Please check your internet connection and '
              'try again.',
          icon: Icons.wifi_off_rounded,
        );
      case 'not-found':
        return LoadFailureView(
          title: 'Not found',
          message:
              'The requested $resource could not be found. It may have been '
              'removed or is not available yet.',
          icon: Icons.search_off,
        );
      case 'invalid-argument':
        return LoadFailureView(
          title: 'Invalid request',
          message:
              'The request for $resource is not valid. Please contact the '
              'administrator if this keeps happening.',
          icon: Icons.error_outline,
        );
      case 'cancelled':
        return const LoadFailureView(
          title: 'Request cancelled',
          message: 'The request was cancelled. Please try again.',
          icon: Icons.cancel_outlined,
        );
      case 'resource-exhausted':
      case 'aborted':
        return const LoadFailureView(
          title: 'Please try again',
          message:
              'The service is busy right now. Please try again in a moment.',
          icon: Icons.hourglass_empty,
        );
    }
  }

  final text = error.toString().toLowerCase();
  if (text.contains('socket') ||
      text.contains('network') ||
      text.contains('offline') ||
      text.contains('failed host lookup')) {
    return const LoadFailureView(
      title: 'Unable to connect',
      message:
          'Unable to connect. Please check your internet connection and try again.',
      icon: Icons.wifi_off_rounded,
    );
  }

  return LoadFailureView(
    title: 'Something went wrong',
    message:
        'Could not load $resource right now. Please try again. If the problem '
        'continues, contact an administrator.',
    icon: Icons.error_outline,
  );
}

void _debugLog(Object error) {
  if (!kDebugMode) return;
  if (error is FirebaseException) {
    debugPrint(
      '[Firestore] ${error.plugin}/${error.code}: ${error.message ?? ''}',
    );
    return;
  }
  debugPrint('[Firestore] unexpected: ${error.runtimeType}');
}
