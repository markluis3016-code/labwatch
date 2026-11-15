import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:labwatch/shared/models/app_user.dart';

AppUser user({
  UserRole role = UserRole.instructor,
  AccountStatus status = AccountStatus.active,
  bool canControlDevices = false,
  List<String> assignedLabIds = const [],
  String displayName = 'Demo Instructor',
  String email = 'instructor@labwatch.demo',
}) {
  return AppUser(
    uid: 'uid-1',
    email: email,
    displayName: displayName,
    role: role,
    status: status,
    canControlDevices: canControlDevices,
    assignedLabIds: assignedLabIds,
  );
}

void main() {
  group('role and status parsing', () {
    test('known values parse', () {
      expect(UserRole.parse('admin'), UserRole.admin);
      expect(UserRole.parse('staff'), UserRole.staff);
      expect(UserRole.parse('instructor'), UserRole.instructor);
      expect(AccountStatus.parse('active'), AccountStatus.active);
      expect(AccountStatus.parse('pending'), AccountStatus.pending);
      expect(AccountStatus.parse('disabled'), AccountStatus.disabled);
    });

    test('unknown or missing status always falls back to disabled', () {
      expect(AccountStatus.parse(null), AccountStatus.disabled);
      expect(AccountStatus.parse('approved'), AccountStatus.disabled);
      expect(AccountStatus.parse(''), AccountStatus.disabled);
    });

    test('unknown role in a document falls back to the least privileged role',
        () async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/u1').set(<String, dynamic>{
        'email': 'user@example.com',
        'displayName': 'Unknown Role',
        // Deliberately absent: role and status.
      });
      final snapshot = await db.doc('users/u1').get();
      final parsed = AppUser.fromDoc(snapshot);

      expect(parsed.role, UserRole.instructor);
      expect(parsed.hasKnownRole, isFalse);
      expect(parsed.status, AccountStatus.disabled);
      expect(parsed.isActive, isFalse);
    });
  });

  group('fromDoc', () {
    test('reads a complete profile and Timestamp createdAt', () async {
      final created = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final db = FakeFirebaseFirestore();
      await db.doc('users/u2').set(<String, dynamic>{
        'email': 'staff@labwatch.demo',
        'displayName': 'Demo Staff',
        'phone': '+63 900 000 0002',
        'role': 'staff',
        'status': 'active',
        'canControlDevices': true,
        'assignedLabIds': ['lab-1', 42, 'lab-2'],
        'createdAt': Timestamp.fromDate(created),
      });

      final parsed = AppUser.fromDoc(await db.doc('users/u2').get());

      expect(parsed.uid, 'u2');
      expect(parsed.email, 'staff@labwatch.demo');
      expect(parsed.displayName, 'Demo Staff');
      expect(parsed.phone, '+63 900 000 0002');
      expect(parsed.role, UserRole.staff);
      expect(parsed.status, AccountStatus.active);
      expect(parsed.canControlDevices, isTrue);
      // Non-string entries are discarded rather than crashing the parser.
      expect(parsed.assignedLabIds, ['lab-1', 'lab-2']);
      // fake_cloud_firestore round-trips through the local timezone.
      expect(parsed.createdAt!.toUtc(), created);
    });

    test('falls back to the legacy fullName field', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/u3').set(<String, dynamic>{
        'email': 'legacy@example.com',
        'fullName': 'Legacy Name',
        'role': 'staff',
        'status': 'active',
      });

      final parsed = AppUser.fromDoc(await db.doc('users/u3').get());
      expect(parsed.displayName, 'Legacy Name');
    });

    test('treats a missing document body as a disabled empty profile',
        () async {
      final db = FakeFirebaseFirestore();
      final parsed = AppUser.fromDoc(await db.doc('users/missing').get());

      expect(parsed.displayName, isEmpty);
      expect(parsed.email, isEmpty);
      expect(parsed.status, AccountStatus.disabled);
      expect(parsed.assignedLabIds, isEmpty);
    });
  });

  group('initials', () {
    test('uses first and last words', () {
      expect(user(displayName: 'Demo Administrator').initials, 'DA');
      expect(user(displayName: '  Grace   Hopper  ').initials, 'GH');
    });

    test('uses one letter for a single name', () {
      expect(user(displayName: 'Ada').initials, 'A');
    });

    test('falls back to the email when the name is empty', () {
      expect(
        user(displayName: '', email: 'staff@labwatch.demo').initials,
        'S',
      );
    });
  });

  group('device-control permission', () {
    test('active administrators may control devices without lab assignments',
        () {
      expect(
        user(role: UserRole.admin, assignedLabIds: const []).mayControlDevices,
        isTrue,
      );
    });

    test('staff need the grant and at least one assigned lab', () {
      expect(
        user(
          role: UserRole.staff,
          canControlDevices: true,
          assignedLabIds: const ['lab-1'],
        ).mayControlDevices,
        isTrue,
      );
      expect(
        user(
            role: UserRole.staff,
            canControlDevices: false,
            assignedLabIds: const ['lab-1']).mayControlDevices,
        isFalse,
      );
      expect(
        user(role: UserRole.staff, canControlDevices: true).mayControlDevices,
        isFalse,
      );
    });

    test('instructors are always read-only, even with a stale grant', () {
      expect(
        user(
          role: UserRole.instructor,
          canControlDevices: true,
          assignedLabIds: const ['lab-1'],
        ).mayControlDevices,
        isFalse,
      );
    });

    test('pending and disabled accounts never control devices', () {
      expect(
        user(
          role: UserRole.admin,
          status: AccountStatus.pending,
          canControlDevices: true,
          assignedLabIds: const ['lab-1'],
        ).mayControlDevices,
        isFalse,
      );
      expect(
        user(
          role: UserRole.staff,
          status: AccountStatus.disabled,
          canControlDevices: true,
          assignedLabIds: const ['lab-1'],
        ).mayControlDevices,
        isFalse,
      );
    });
  });
}
