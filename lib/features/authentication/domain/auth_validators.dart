/// Pure validators shared by the login, sign-up and reset screens.
/// Kept free of Flutter/Firebase imports so they are easy to unit test.
class AuthValidators {
  AuthValidators._();

  static final RegExp emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _phonePattern = RegExp(r'^\+?[0-9 ()\-]{7,20}$');
  static final RegExp _hasUpper = RegExp(r'[A-Z]');
  static final RegExp _hasLower = RegExp(r'[a-z]');
  static final RegExp _hasDigit = RegExp(r'[0-9]');

  static String? email(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter your email address.';
    if (text.length > 254) return 'That email address is too long.';
    if (!emailPattern.hasMatch(text)) return 'Enter a valid email address.';
    return null;
  }

  static String? password(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'Enter a password.';
    if (text.length < 8) return 'Use at least 8 characters.';
    if (!_hasUpper.hasMatch(text)) {
      return 'Include at least one uppercase letter.';
    }
    if (!_hasLower.hasMatch(text)) {
      return 'Include at least one lowercase letter.';
    }
    if (!_hasDigit.hasMatch(text)) return 'Include at least one number.';
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if ((value ?? '').isEmpty) return 'Confirm your password.';
    if (value != password) return 'Passwords do not match.';
    return null;
  }

  static String? fullName(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter your full name.';
    if (text.length < 2) return 'Enter your full name.';
    if (text.length > 80) return 'That name is too long.';
    return null;
  }

  static String? phone(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter your contact number.';
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 7) return 'Enter a valid contact number.';
    if (!_phonePattern.hasMatch(text)) return 'Enter a valid contact number.';
    return null;
  }
}
