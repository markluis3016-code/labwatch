/// A safe, user-facing failure. Never carries raw Firebase error details.
class AppFailure implements Exception {
  const AppFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
