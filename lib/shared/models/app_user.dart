import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole {
  admin,
  instructor,
  staff;

  static UserRole? parse(String? value) {
    for (final role in UserRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }

  String get label => switch (this) {
        UserRole.admin => 'Administrator',
        UserRole.instructor => 'Instructor',
        UserRole.staff => 'Staff',
      };
}

enum AccountStatus {
  active,
  disabled,
  pending;

  static AccountStatus parse(String? value) {
    for (final status in AccountStatus.values) {
      if (status.name == value) return status;
    }
    // Unknown/missing status must never grant access.
    return AccountStatus.disabled;
  }

  String get label => switch (this) {
        AccountStatus.active => 'Active',
        AccountStatus.disabled => 'Disabled',
        AccountStatus.pending => 'Pending',
      };
}

/// Profile stored at `users/{uid}`. Role, status and permissions are written
/// only by admins (see firestore.rules); the client treats them as read-only.
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.status,
    this.hasKnownRole = true,
    this.canControlDevices = false,
    this.assignedLabIds = const [],
    this.phone = '',
    this.statusNote,
    this.createdAt,
  });

  final String uid;
  final String email;
  final String displayName;
  final UserRole role;
  final AccountStatus status;

  /// False when the stored role is missing or not a recognised value. Such
  /// accounts are blocked instead of being silently treated as a valid role.
  final bool hasKnownRole;

  /// Staff need this explicit grant; admins always have it.
  final bool canControlDevices;
  final List<String> assignedLabIds;
  final String phone;

  /// Optional administrator note shown on the pending/disabled screen.
  final String? statusNote;
  final DateTime? createdAt;

  bool get isActive => status == AccountStatus.active;
  bool get isPending => status == AccountStatus.pending;
  bool get isAdmin => role == UserRole.admin;
  bool get isStaff => role == UserRole.staff;
  bool get isInstructor => role == UserRole.instructor;

  bool get mayControlDevices =>
      isActive &&
      (isAdmin || (isStaff && canControlDevices && assignedLabIds.isNotEmpty));

  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return email.isNotEmpty ? email.substring(0, 1).toUpperCase() : '?';
    }
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final assigned = data['assignedLabIds'];
    final note = _nonEmptyString(data['statusNote']);
    final created = data['createdAt'];
    final parsedRole = UserRole.parse(_stringOrNull(data['role']));

    return AppUser(
      uid: doc.id,
      email: _string(data['email']),
      displayName: _nonEmptyString(data['displayName']) ??
          _nonEmptyString(data['fullName']) ??
          '',
      // An unknown role must not silently gain staff-level permissions, and
      // the router blocks the account entirely until an admin fixes it.
      role: parsedRole ?? UserRole.instructor,
      status: AccountStatus.parse(_stringOrNull(data['status'])),
      hasKnownRole: parsedRole != null,
      canControlDevices: data['canControlDevices'] == true,
      assignedLabIds: assigned is List
          ? assigned.whereType<String>().toList(growable: false)
          : const <String>[],
      phone: _string(data['phone']),
      statusNote: note,
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}

String _string(Object? value) => value is String ? value : '';

String? _stringOrNull(Object? value) => value is String ? value : null;

String? _nonEmptyString(Object? value) {
  final text = _string(value).trim();
  return text.isEmpty ? null : text;
}
