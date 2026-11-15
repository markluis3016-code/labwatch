import 'package:flutter_test/flutter_test.dart';
import 'package:labwatch/features/authentication/domain/auth_validators.dart';

void main() {
  group('email', () {
    test('accepts normal addresses', () {
      expect(AuthValidators.email('admin@labwatch.demo'), isNull);
      expect(AuthValidators.email('  user+tag@example.co.uk  '), isNull);
    });

    test('rejects empty, malformed and over-long addresses', () {
      expect(AuthValidators.email(null), isNotNull);
      expect(AuthValidators.email('   '), isNotNull);
      expect(AuthValidators.email('not-an-email'), isNotNull);
      expect(AuthValidators.email('a@b'), isNotNull);
      expect(AuthValidators.email('${'a' * 250}@example.com'), isNotNull);
    });
  });

  group('password', () {
    test('accepts the documented demo passwords', () {
      expect(AuthValidators.password('Admin@12345'), isNull);
      expect(AuthValidators.password('Staff@12345'), isNull);
      expect(AuthValidators.password('Instructor@12345'), isNull);
    });

    test('rejects weak passwords with a specific reason', () {
      expect(AuthValidators.password(''), contains('Enter'));
      expect(AuthValidators.password('Ab1'), contains('8 characters'));
      expect(AuthValidators.password('abcdefg1'), contains('uppercase'));
      expect(AuthValidators.password('ABCDEFG1'), contains('lowercase'));
      expect(AuthValidators.password('Abcdefgh'), contains('number'));
    });

    test('confirmation must match exactly', () {
      expect(
          AuthValidators.confirmPassword('Admin@12345', 'Admin@12345'), isNull);
      expect(AuthValidators.confirmPassword('', 'Admin@12345'), isNotNull);
      expect(AuthValidators.confirmPassword('Admin@1234', 'Admin@12345'),
          isNotNull);
    });
  });

  group('full name', () {
    test('accepts a normal name and trims whitespace', () {
      expect(AuthValidators.fullName('  Demo Administrator  '), isNull);
    });

    test('rejects empty, single-character and over-long names', () {
      expect(AuthValidators.fullName(null), isNotNull);
      expect(AuthValidators.fullName('  '), isNotNull);
      expect(AuthValidators.fullName('A'), isNotNull);
      expect(AuthValidators.fullName('A' * 81), isNotNull);
    });
  });

  group('phone', () {
    test('accepts common formats', () {
      expect(AuthValidators.phone('+63 900 000 0001'), isNull);
      expect(AuthValidators.phone('0917-123-4567'), isNull);
      expect(AuthValidators.phone('(02) 8123 4567'), isNull);
    });

    test('rejects empty, short and non-numeric values', () {
      expect(AuthValidators.phone(null), isNotNull);
      expect(AuthValidators.phone(''), isNotNull);
      expect(AuthValidators.phone('12345'), isNotNull);
      expect(AuthValidators.phone('call me'), isNotNull);
    });
  });
}
