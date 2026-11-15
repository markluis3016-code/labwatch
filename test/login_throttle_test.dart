import 'package:flutter_test/flutter_test.dart';
import 'package:labwatch/features/authentication/data/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('five failures lock the client for a few minutes and reset clears it',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final throttle = LoginThrottle();

    expect(await throttle.remainingLock(), isNull);

    for (var attempt = 0; attempt < 4; attempt++) {
      await throttle.recordFailure();
      expect(
        await throttle.remainingLock(),
        isNull,
        reason: 'attempt ${attempt + 1} should not lock yet',
      );
    }

    await throttle.recordFailure();
    final lock = await throttle.remainingLock();
    expect(lock, isNotNull);
    expect(lock!.inMinutes, inInclusiveRange(4, 5));

    await throttle.reset();
    expect(await throttle.remainingLock(), isNull);
  });

  test('an expired lock clears itself', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'login_fail_count': 5,
      'login_locked_until': DateTime.now()
          .subtract(const Duration(seconds: 1))
          .millisecondsSinceEpoch,
    });
    final throttle = LoginThrottle();

    expect(await throttle.remainingLock(), isNull);
    // The expired lock and counter were cleared.
    expect(await throttle.remainingLock(), isNull);
  });
}
