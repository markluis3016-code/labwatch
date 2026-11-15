# LabWatch authentication and account management

This document covers the Firebase project setup, security model, demo accounts,
day-to-day administration and a manual test checklist for the authentication
system.

- Firebase project: `labwatch-b477c`
- Firestore database: `(default)`
- Flutter app entry point: `lib/main.dart`
- Rules: `firestore.rules`
- Indexes: `firestore.indexes.json`
- Demo seed: `scripts/seed-demo-accounts.mjs`

---

## 1. How the system works

### Public registration

1. The visitor opens **Create account**.
2. The app creates a Firebase Auth email/password user.
3. It writes `users/{uid}` with:
   - `role: "instructor"`
   - `status: "pending"`
   - `canControlDevices: false`
   - `assignedLabIds: []`
   - `displayName`, `email`, `phone`
   - server-stamped `createdAt` / `updatedAt`
4. It sends a verification email.
5. The router sends the user to **Verify email**.
6. After verification, the user sees **Awaiting approval**.
7. An administrator approves the account and chooses **Staff** or
   **Instructor**. The user is redirected to the dashboard as soon as the
   profile stream reports `status: "active"`.

A public sign-up can never choose `admin`, `active`, or device-control
permissions. The Firestore rules enforce this independently of the UI.

### Administrator accounts

Administrator accounts are deliberately not creatable from the public app or
from the admin user screen. Use the Admin SDK seed script or the Firebase
Console. This prevents privilege escalation through self-service registration.

### Roles

| Capability | Administrator | Staff | Instructor |
|---|---|---|---|
| Sign in / read laboratory telemetry | Yes | Yes | Yes |
| Edit own name and contact number | Yes | Yes | Yes |
| Approve / reject accounts | Yes | No | No |
| Change roles, status, lab assignments | Yes | No | No |
| Control devices | All labs | Assigned labs, if granted | No |
| Read all activity | Yes | Own only | Own only |
| See admin screens | Yes | No | No |

Device control for Staff requires **both** `canControlDevices: true` **and** at
least one entry in `assignedLabIds`. Administrators bypass lab assignment.

---

## 2. Firebase Console setup

Do these once per Firebase project.

1. **Authentication → Sign-in method**
   - Enable **Email/Password**.
   - Leave Email link sign-in disabled unless you add that flow later.
2. **Authentication → Settings → Authorized domains**
   - Keep `localhost` for development.
   - Add your production web domain if you ship a web build.
3. **Authentication → Templates**
   - Review the **Email address verification** and **Password reset** emails.
   - Set a recognizable sender name and reply-to address.
   - Customize the action URL only if you use Firebase Hosting with a custom
     action handler; the default Firebase handler is fine.
4. **Firestore Database**
   - Confirm the `(default)` database exists.
   - Deploy the rules and indexes from this repository (next section).
5. **Project settings → Your apps**
   - The Android app and `lib/firebase_options.dart` are already configured for
     `labwatch-b477c`. Re-run `flutterfire configure` only if you add a
     platform (iOS, web, Windows, etc.).
6. **API key restrictions (recommended)**
   - In Google Cloud Console → APIs & Services → Credentials, restrict the
     Firebase API keys to the Android package name / web domains you actually
     use.

### Deploy rules and indexes

From the repository root:

```powershell
firebase login
firebase use labwatch-b477c
firebase deploy --only firestore:rules,firestore:indexes --project labwatch-b477c
```

The activity list needs the composite index on
`activity: userId ASC, timestamp DESC`. The first query after a fresh deploy
may fail for a few minutes while the index builds; the Activity screen explains
this and offers Retry.

### Local emulators (optional)

```powershell
firebase emulators:start --only auth,firestore
```

The emulator UI is at `http://127.0.0.1:4000`.

The current Flutter app points at the production Firebase project. To run the
app against the emulators, add the standard `useAuthEmulator` /
`useFirestoreEmulator` calls in `lib/main.dart` behind a debug-only
`--dart-define`, for example:

```dart
const useEmulators = bool.fromEnvironment('USE_FIREBASE_EMULATORS');
if (useEmulators) {
  await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
  FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
}
```

On the Android emulator, use `10.0.2.2` instead of `127.0.0.1`.

---

## 3. Demo accounts

| Role | Email | Password |
|---|---|---|
| Administrator | `admin@labwatch.demo` | `Admin@12345` |
| Staff | `staff@labwatch.demo` | `Staff@12345` |
| Instructor | `instructor@labwatch.demo` | `Instructor@12345` |

The administrator gets `canControlDevices: true` and no required lab
assignments (administrators bypass lab scoping). Staff is granted device
control for `lab-1` so that path is demonstrable; set
`canControlDevices: false` if you prefer a read-only staff demo. The instructor
is read-only with no lab assignments. The script also creates `labs/lab-1` if
it is missing.

> These passwords are for a development/demo project only. Never reuse them in
> production, and delete or disable the accounts before a real deployment.

### Create a service account (once)

The seed script needs trusted credentials. The Flutter app never contains one.

1. Open Google Cloud Console → **IAM & Admin → Service accounts**.
2. Select the Firebase Admin SDK service account (or create one).
3. **Keys → Add key → Create new key → JSON**.
4. Save the JSON outside the repository, or anywhere covered by `.gitignore`.
5. Grant the account a role that can manage Firebase Auth users and Firestore,
   for example **Firebase Admin SDK Administrator Service Account**
   (`roles/firebase.sdkAdminServiceAgent`) or the narrower
   **Firebase Authentication Admin** + **Cloud Datastore User** pair.

Never commit the JSON key. `.gitignore` already ignores `service-account*.json`,
`*-firebase-adminsdk-*.json` and `.firebase/`.

Alternatively, authenticate Application Default Credentials:

```powershell
gcloud auth application-default login
```

### Run the seed

```powershell
cd scripts
npm install
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\service-account.json"
npm run seed
```

or, if ADC is configured:

```powershell
cd scripts
npm run seed
```

or, for a one-off run from an already authenticated Firebase CLI session:

```powershell
$cfg = Get-Content "$env:USERPROFILE\.config\configstore\firebase-tools.json" -Raw | ConvertFrom-Json
$env:FIREBASE_ACCESS_TOKEN = $cfg.tokens.access_token
cd scripts
npm run seed
```

`FIREBASE_ACCESS_TOKEN` is a short-lived OAuth token. Use it only from a
trusted local CLI/CI session; never put it in the Flutter app or commit it.

The script is idempotent. Missing Auth accounts are created with the documented
demo password. Existing accounts are marked verified and re-merged into
Firestore, but **their passwords are never changed**. Existing `createdAt`
values are preserved. If you need to restore an original demo password, reset
it in the Firebase Console instead of re-running the script.

To seed the emulators instead:

```powershell
$env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
npm run seed
```

### First production administrator without the script

If you cannot use a service account, create the Auth user in **Authentication →
Users**, then create `users/{uid}` manually in the Firestore console:

```json
{
  "email": "you@example.com",
  "displayName": "Your Name",
  "phone": "+63 900 000 0000",
  "role": "admin",
  "status": "active",
  "canControlDevices": true,
  "assignedLabIds": [],
  "createdAt": "<server timestamp>",
  "updatedAt": "<server timestamp>"
}
```

Mark the Auth user's email as verified first, otherwise the app will send the
account to the verify-email screen.

---

## 4. Account lifecycle

### Approve

1. Sign in as an administrator.
2. Open **Users**.
3. Find the pending account (filter **Pending**).
4. Choose **Approve** and select **Staff** or **Instructor**.
5. The user's open app moves to the dashboard automatically; no re-login is
   required.

### Reject / disable / reactivate

- **Reject** marks the account `disabled` and stores a status note.
- **Deactivate** does the same for an already-active account.
- **Activate** restores `active`.
- Accounts can never be moved back to `pending` from the admin screen.
- Prefer disabling over deleting. Deleting an Auth user leaves the Firestore
  profile behind unless you clean it up separately.

### Change role or lab assignments

Use **Users → account → Change role** and **Assign labs**. Only Staff and
Instructor are offered; Administrator accounts must be managed with the Admin
SDK. The app blocks all self-management actions, and the Firestore rules also
reject changes to an administrator's own `role` or `status` (the lockout guard).

### Self-service profile

Users may edit only `displayName` and `phone` on the **Account** screen. Email,
role, status, permissions and lab assignments are read-only in the app and
rejected by the rules outside the admin branch.

---

## 5. Security model

`firestore.rules` is the real enforcement layer. The router guards are a UX
layer only.

- `active()` requires all of:
  - a signed-in Firebase user,
  - `email_verified == true` in the Auth token,
  - an existing `users/{uid}` document,
  - `status == "active"`.
- A missing or unknown `role` is detected and the account is sent to the
  account-problem screen instead of being assigned a dashboard. A missing or
  unknown `status` is treated as disabled.
- After email verification the app forces an ID-token refresh, so Firestore
  rules see `email_verified == true` immediately rather than waiting for the
  cached token to expire.
- Self-read of `users/{uid}` is allowed for any signed-in user so pending and
  disabled accounts can render the correct holding screen. Reading other users
  requires an active administrator.
- Public sign-up may create only its own pending Instructor profile, with the
  exact field allowlist, matching email, no lab assignments and no device
  grant.
- Users may update only `displayName`, `photoUrl`, `phone` and a server-stamped
  `updatedAt`. Role, status, permissions and lab assignments are not in that
  allowlist.
- Administrators may update accounts but cannot change their own `role` or
  `status`, and all role/status values are validated.
- Administrators cannot delete their own account.
- Device commands require `canControlLab(labId)`: administrators bypass lab
  scoping; staff need the explicit grant and the lab in `assignedLabIds`.
- Clients can never write telemetry or mark a command as succeeded.
- Activity entries are append-only, attributed to the caller, server-stamped,
  length-limited and restricted to a fixed action list. Administrator actions
  such as `user_approved` can only be written by an active administrator.
- Sign-in maps Firebase error codes to specific messages where Firebase exposes
  them (invalid email, user not found, wrong password, disabled account,
  network, rate limit, configuration errors). If Email Enumeration Protection
  is enabled, Firebase returns `invalid-credential` for both an unknown email
  and a wrong password, so that one case remains intentionally ambiguous.
  Password reset always reports the same outcome whether or not an account
  exists.
- The client login throttle (5 failures / 5 minutes) is a UX safeguard only;
  Firebase Auth performs the real rate limiting.

> Client-written activity is best-effort auditing. If you need a tamper-proof
> trail, move activity writes into a Cloud Function and deny client writes.

---

## 6. Testing

### Automated tests

```powershell
flutter analyze
flutter test
```

Covered by the test suite:

- `test/auth_validators_test.dart` — email, password, confirmation, name and
  phone rules, including the demo passwords.
- `test/app_user_test.dart` — role/status parsing, safe defaults for malformed
  documents, legacy `fullName` fallback, initials and device-control
  permissions.
- `test/route_access_test.dart` — pending/disabled denial, instructor
  read-only access, staff lab/grant scoping and administrator access.
- `test/auth_screens_test.dart` — login and sign-up render and validate empty
  submissions; sign-up exposes no role picker.
- `test/telemetry_validator_test.dart` / `test/widget_test.dart` — existing
  telemetry behaviour.

Rules are not covered by `flutter test`; use the emulator or a staging project
for the direct-write checks below.

### Manual checklist

Run against a staging project or the emulators. Sign out between scenarios
unless stated otherwise.

1. **Sign up** with a new email. Confirm the account lands on **Verify email**,
   and Firestore shows `role: instructor`, `status: pending`,
   `canControlDevices: false`, `assignedLabIds: []`.
2. **No privilege choice**: the sign-up screen has no role selector and no way
   to request Administrator access.
3. **Verification gate**: before clicking the email link, try opening
   `/dashboard`. The app returns to **Verify email**. Resend works.
4. **Verify** via the email link, press **I've verified**, and confirm the app
   moves to **Awaiting approval**, not the dashboard.
5. **Pending gate**: a pending user cannot reach `/dashboard`, `/admin/users`,
   `/activity`, `/control` or any Firestore-protected data.
6. **Approve as Staff**: as the demo administrator, approve the pending user as
   Staff. Without a reload, the user's app moves to the dashboard.
7. **Approve as Instructor**: repeat with another account. The account is
   read-only and has no device-control action.
8. **Reject**: reject a pending account. The user sees the account-problem
   screen on the next check, with `status: disabled`.
9. **Deactivate / reactivate**: disable an active user, confirm they are
   blocked, then reactivate and confirm access returns.
10. **Role guard by UI**: sign in as Staff or Instructor and try `/admin/users`,
    `/labs` or `/settings`. The router redirects to `/dashboard`.
11. **Device-control guard**: as Staff with no lab assignment, `/control` is
    unavailable. Assign `lab-1`, grant device control, and confirm it becomes
    available. Revoke either condition and confirm it becomes unavailable
    again. Instructor never gets it.
12. **Self-edit only**: change your name and phone on **Account**. Then attempt
    to change your own `role` or `status` with a direct Firestore client; the
    rules must reject it.
13. **Admin self-lockout guard**: an administrator cannot change their own role
    or status in the UI, and a direct write must be rejected by the rules.
14. **Login throttle and errors**: enter a wrong password five times. The sixth
    attempt is locally blocked for five minutes and the message is generic.
    A password reset request for an unknown email reports the same result as a
    known one.
15. **Activity trail**: sign in/out, update a profile, approve a user and change
    a role. The administrator sees all entries; Staff and Instructor see only
    their own. Entries cannot be edited or deleted by clients.
16. **Direct rules checks** (emulator or staging):
    - Client write to `labs/lab-1/telemetry/latest` → denied.
    - Client create of `users/{otherUid}` → denied.
    - Self sign-up with `role: "admin"` or `status: "active"` → denied.
    - Client update of own `role`/`status` → denied.
    - Client update of another user's `displayName` → denied unless admin.
    - Client update/delete of `activity/{id}` → denied.

### Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `operation-not-allowed` on login or sign-up | Email/Password provider disabled | Enable it in Authentication → Sign-in method |
| New user stuck on verify after clicking the link | Firebase user not reloaded yet | Use **I've verified** or restart the app |
| Admin account sent to verify-email | Auth email not marked verified | Verify the email or set `emailVerified` with the Admin SDK |
| `permission-denied` for a valid user | `status` not `active`, email unverified, or rules not deployed | Check the profile and deploy rules |
| Activity screen errors right after deploy | Composite index is still building | Wait and press Retry; check the index in Firestore → Indexes |
| Seed script cannot find credentials | No service account / ADC | Set `GOOGLE_APPLICATION_CREDENTIALS` or run `gcloud auth application-default login` |
| Admin user screen is empty | Signed-in account is not an active administrator | Use the seeded admin or fix `users/{uid}` |
| Demo login says “Incorrect email or password” | The demo accounts were never created, the password was changed, or the app is using another project | Run `npm run seed`, verify the three emails in Authentication → Users, then reset the password in the Console if needed |
| Demo accounts exist but app rejects them | Missing/invalid Firestore profile, unverified email, or `status` not `active` | Re-run `npm run seed`; it verifies the Auth user and re-merges the profile without changing the password |
