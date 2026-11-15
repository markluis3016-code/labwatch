# LabWatch

IoT-based laboratory monitoring, scheduling and equipment inventory app
(Flutter + Firebase).

The authentication and account-management layer is implemented end to end:
public registration, email verification, administrator approval, role-based
routing, profile editing, an append-only activity trail and hardened Firestore
rules.

## Quick start

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

The app is configured for the Firebase project `labwatch-b477c`
(`lib/firebase_options.dart`, `android/app/google-services.json`).

Before the first run, enable **Email/Password** in
Firebase Console → Authentication → Sign-in method, and deploy the rules:

```powershell
firebase use labwatch-b477c
firebase deploy --only firestore:rules,firestore:indexes --project labwatch-b477c
```

## Demo accounts

| Role | Email | Password |
|---|---|---|
| Administrator | `admin@labwatch.demo` | `Admin@12345` |
| Staff | `staff@labwatch.demo` | `Staff@12345` |
| Instructor | `instructor@labwatch.demo` | `Instructor@12345` |

Create them with the Admin SDK seed script — never from the Flutter app:

```powershell
cd scripts
npm install
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\service-account.json"
npm run seed
```

Re-running the script never changes an existing password; it verifies the Auth
user and repairs/merges the Firestore profile. Full service-account, short-lived
CLI token, Firebase Console, emulator and troubleshooting instructions are in
**[docs/AUTH_SETUP.md](docs/AUTH_SETUP.md)**.

> Demo passwords are for development only. Delete or disable the demo accounts
> before a real deployment.

## Authentication flow

1. **Sign up** creates an Auth user and a `users/{uid}` profile with
   `role: instructor`, `status: pending`, no lab assignments and no device
   grant. The screen offers no role choice.
2. The user must **verify their email** before seeing the pending screen.
3. An **administrator approves** the account as Staff or Instructor.
4. The live profile stream moves the user to the correct dashboard without a
   re-login.
5. Pending, disabled and unverified accounts cannot reach protected routes or
   Firestore data.

Administrator accounts are created with the Admin SDK or the Firebase Console,
not through public sign-up or the in-app user screen.

### Role capabilities

| Capability | Administrator | Staff | Instructor |
|---|---|---|---|
| View labs and telemetry | Yes | Yes | Yes |
| Edit own name / phone | Yes | Yes | Yes |
| Approve/disable users, change roles/labs | Yes | No | No |
| Control devices | All labs | Assigned labs, if granted | No |
| Read activity | All users | Own only | Own only |

Staff device control requires both `canControlDevices: true` and a non-empty
`assignedLabIds`. Administrators bypass lab assignment.

## Data model

| Path | Purpose | Written by |
|---|---|---|
| `users/{uid}` | Profile, role, status, device grant, lab assignments | Self (cosmetic fields), admin, Admin SDK |
| `labs/{labId}` | Laboratory metadata | Admin / Admin SDK |
| `labs/{labId}/telemetry/latest` | `occupied`, `light` / `ac`, `sensorTimestamp`, `receivedAt` | IoT gateway / Cloud Function only |
| `labs/{labId}/commands/{id}` | Queued device commands (`pending`) | Authorised users; executed server-side |
| `activity/{id}` | Append-only audit log | Signed-in active users, as themselves |

## Feature status

| Feature | Status |
|---|---|
| Email/password sign-in, validation, safe errors, sign-out | Implemented |
| Sign-up as pending Instructor, email verification | Implemented |
| Administrator approval, rejection, activation, role and lab management | Implemented |
| Live role/status routing guards and role-specific dashboards | Implemented |
| Forgot password / reset email | Implemented |
| Profile editing (name and phone only) | Implemented |
| Activity trail (own activity; admins see all) | Implemented |
| Client login throttle (5 tries / 5 minutes) | Implemented (UX only) |
| Hardened Firestore rules and activity index | Written; deploy with the command above |
| Flutter unit/widget tests | Implemented |
| Live sensor data | Requires your IoT gateway / Cloud Function writing `telemetry/latest` |
| Demo mode | Simulated; always labelled SAMPLE DATA; off by default |
| Alerts + FCM, scheduling, equipment checklists, inventory, energy, PDF reports, remote-control UI/function | Not built yet (screens say so honestly) |

## Tests

```powershell
flutter analyze
flutter test
```

The automated suite covers validators, model/permission logic, route access and
the login/sign-up screens. The manual 16-scenario checklist, including direct
Firestore rules checks, is in
[docs/AUTH_SETUP.md](docs/AUTH_SETUP.md#6-testing).

## Security notes

- Firestore rules are the enforcement layer; router guards are only UX.
- `active()` requires a signed-in user, a verified email, an existing profile
  and `status == "active"`.
- Public sign-up can create only its own pending Instructor profile with an
  exact field allowlist. Attempts to self-assign `admin`, `active` or a device
  grant are rejected by the rules.
- Users may self-edit only `displayName`, `photoUrl`, `phone` and a
  server-stamped `updatedAt`.
- Administrators cannot change their own role or status, and cannot delete
  their own account.
- Clients can never write telemetry or mark device commands as succeeded.
- Activity entries are append-only, server-stamped, length-limited and
  restricted to a fixed action list. Extend that list when a module starts
  writing activity.
- Login errors are generic to avoid account enumeration; password reset always
  reports the same result.
- Device commands must be executed by a Cloud Function that re-checks
  permissions, requires recent re-authentication, talks to hardware over TLS
  and updates state only after the device confirms.

## Next build steps

Alerts + empty-room detection (check the schedule first) → scheduling with
conflict checks → equipment checklists → inventory → energy → PDF reports →
remote control (Cloud Function + re-authentication).
