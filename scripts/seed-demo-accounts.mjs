#!/usr/bin/env node
/**
 * Creates the three LabWatch demo accounts with the Firebase Admin SDK.
 *
 * This script must run with trusted credentials. It is intentionally NOT part
 * of the Flutter app: public sign-up can only create a pending Instructor.
 *
 * Usage (from the repository root):
 *
 *   cd scripts
 *   npm install
 *   set GOOGLE_APPLICATION_CREDENTIALS=C:\path\to\service-account.json
 *   npm run seed
 *
 * PowerShell:
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\service-account.json"
 *   npm run seed
 *
 * Against the local emulator (no service account needed):
 *   $env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"
 *   $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
 *   npm run seed
 *
 * From an already authenticated Firebase CLI session (one-off, trusted use):
 *   $env:FIREBASE_ACCESS_TOKEN = "<short-lived OAuth access token>"
 *   npm run seed
 *
 * The script is idempotent: existing Auth users are verified
 * (emailVerified=true, disabled=false) and their display name is updated, but
 * their password is NEVER changed. Only missing accounts are created with the
 * documented demo password. Profile documents are merged and existing
 * createdAt values are preserved.
 */

import { readFileSync } from 'node:fs';

import { applicationDefault, cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID ?? 'labwatch-b477c';
const AUTH_EMULATOR = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const FIRESTORE_EMULATOR = process.env.FIRESTORE_EMULATOR_HOST;
const SERVICE_ACCOUNT_PATH =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ?? process.env.SERVICE_ACCOUNT_PATH;
const ACCESS_TOKEN = process.env.FIREBASE_ACCESS_TOKEN;

if (Boolean(AUTH_EMULATOR) !== Boolean(FIRESTORE_EMULATOR)) {
  console.warn(
    'Warning: set both FIREBASE_AUTH_EMULATOR_HOST and ' +
      'FIRESTORE_EMULATOR_HOST, or neither. Mixed targets are not supported.',
  );
}

const USING_EMULATORS = Boolean(AUTH_EMULATOR && FIRESTORE_EMULATOR);

// The Admin SDK can authenticate with a bare OAuth token, but its Firestore
// client cannot (it needs a certificate/ADC credential). In that case profiles
// are written through the Firestore REST API with the same token.
const USING_REST_FIRESTORE =
  !USING_EMULATORS && !SERVICE_ACCOUNT_PATH && Boolean(ACCESS_TOKEN);

const DEMO_LAB = {
  id: 'lab-1',
  name: 'Laboratory 1',
  description: 'Demo laboratory used by the LabWatch sample dashboards.',
};

/**
 * role/status mirror exactly what an administrator would set. Demo staff get
 * device control for lab-1 so the control path can be demonstrated; the
 * instructor stays read-only.
 */
const DEMO_ACCOUNTS = [
  {
    email: 'admin@labwatch.demo',
    password: 'Admin@12345',
    displayName: 'Demo Administrator',
    phone: '+63 900 000 0001',
    role: 'admin',
    status: 'active',
    canControlDevices: true,
    // Administrators bypass lab assignment, so no labs are required here.
    assignedLabIds: [],
  },
  {
    email: 'staff@labwatch.demo',
    password: 'Staff@12345',
    displayName: 'Demo Staff',
    phone: '+63 900 000 0002',
    role: 'staff',
    status: 'active',
    canControlDevices: true,
    assignedLabIds: [DEMO_LAB.id],
  },
  {
    email: 'instructor@labwatch.demo',
    password: 'Instructor@12345',
    displayName: 'Demo Instructor',
    phone: '+63 900 000 0003',
    role: 'instructor',
    status: 'active',
    canControlDevices: false,
    assignedLabIds: [],
  },
];

function buildApp() {
  if (USING_EMULATORS) {
    // The emulators accept any project id and do not validate credentials.
    return initializeApp({ projectId: PROJECT_ID });
  }

  const serviceAccountPath = SERVICE_ACCOUNT_PATH;

  if (serviceAccountPath) {
    let parsed;
    try {
      parsed = JSON.parse(readFileSync(serviceAccountPath, 'utf8'));
    } catch (error) {
      throw new Error(
        `Could not read the service account file at "${serviceAccountPath}": ${error.message}`,
      );
    }
    return initializeApp({
      credential: cert(parsed),
      projectId: parsed.project_id ?? PROJECT_ID,
    });
  }

  // Short-lived token from a trusted local CLI/CI session. Never ship this
  // token in the Flutter app and never commit it.
  const accessToken = ACCESS_TOKEN;
  if (accessToken) {
    return initializeApp({
      credential: {
        getAccessToken: async () => ({
          access_token: accessToken,
          expires_in: 3600,
        }),
      },
      projectId: PROJECT_ID,
    });
  }

  // Works when gcloud application-default credentials are configured.
  return initializeApp({
    credential: applicationDefault(),
    projectId: PROJECT_ID,
  });
}

async function ensureAuthUser(auth, account) {
  try {
    const existing = await auth.getUserByEmail(account.email);
    // Deliberately do not touch the password of an existing account. This
    // keeps the script safe to re-run after a real password change.
    await auth.updateUser(existing.uid, {
      displayName: account.displayName,
      emailVerified: true,
      disabled: false,
    });
    return { uid: existing.uid, created: false };
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
    const created = await auth.createUser({
      email: account.email,
      password: account.password,
      displayName: account.displayName,
      emailVerified: true,
      disabled: false,
    });
    return { uid: created.uid, created: true };
  }
}

async function upsertProfile(db, uid, account) {
  const ref = db.doc(`users/${uid}`);
  const snapshot = await ref.get();
  const existingCreatedAt = snapshot.exists
    ? snapshot.get('createdAt')
    : undefined;

  await ref.set(
    {
      displayName: account.displayName,
      email: account.email,
      phone: account.phone,
      role: account.role,
      status: account.status,
      canControlDevices: account.canControlDevices,
      assignedLabIds: account.assignedLabIds,
      // Clear a note left by a previous rejection so the demo account is not
      // shown as rejected while it is active.
      statusNote: FieldValue.delete(),
      createdAt: existingCreatedAt ?? FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function ensureLab(db, lab) {
  const ref = db.doc(`labs/${lab.id}`);
  const snapshot = await ref.get();
  await ref.set(
    {
      name: lab.name,
      description: lab.description,
      createdAt: snapshot.exists
        ? snapshot.get('createdAt')
        : FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

/** Minimal Firestore REST client for the FIREBASE_ACCESS_TOKEN path. */
class RestFirestore {
  constructor(projectId, accessToken) {
    this.baseUrl =
      `https://firestore.googleapis.com/v1/projects/${projectId}` +
      '/databases/(default)/documents';
    this.accessToken = accessToken;
  }

  async request(method, path, body) {
    const response = await fetch(`${this.baseUrl}/${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${this.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });

    if (response.status === 404) return null;
    if (!response.ok) {
      const detail = await response.text();
      throw new Error(
        `Firestore REST ${method} ${path} failed (${response.status}): ${detail}`,
      );
    }
    return response.json();
  }

  get(path) {
    return this.request('GET', path);
  }

  replace(path, fields) {
    return this.request('PATCH', path, { fields });
  }
}

const REST_VALUE_KEYS = new Set([
  'nullValue',
  'booleanValue',
  'integerValue',
  'doubleValue',
  'timestampValue',
  'stringValue',
  'bytesValue',
  'referenceValue',
  'geoPointValue',
  'arrayValue',
  'mapValue',
]);

function toRestValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(toRestValue) } };
  }
  // A value read back from the REST API is already in Firestore's encoding.
  if (typeof value === 'object') {
    const keys = Object.keys(value);
    if (keys.length === 1 && REST_VALUE_KEYS.has(keys[0])) return value;
  }
  throw new Error(`Cannot encode ${typeof value} as a Firestore value.`);
}

/**
 * Replaces a document while preserving unknown existing fields. Used only by
 * the REST path because merge/delete field sentinels are Admin-SDK specific.
 */
async function replaceRestDocument(store, path, updates) {
  const existing = await store.get(path);
  const fields = { ...(existing?.fields ?? {}) };

  for (const [key, value] of Object.entries(updates)) {
    if (value === undefined) {
      delete fields[key];
    } else {
      fields[key] = toRestValue(value);
    }
  }

  await store.replace(path, fields);
  return fields;
}

async function upsertProfileRest(store, uid, account) {
  const path = `users/${uid}`;
  const existing = await store.get(path);
  const now = new Date();
  await replaceRestDocument(store, path, {
    displayName: account.displayName,
    email: account.email,
    phone: account.phone,
    role: account.role,
    status: account.status,
    canControlDevices: account.canControlDevices,
    assignedLabIds: account.assignedLabIds,
    // Clear a note left by a previous rejection.
    statusNote: undefined,
    createdAt: existing?.fields?.createdAt ?? now,
    updatedAt: now,
  });
}

async function ensureLabRest(store, lab) {
  const path = `labs/${lab.id}`;
  const existing = await store.get(path);
  const now = new Date();
  await replaceRestDocument(store, path, {
    name: lab.name,
    description: lab.description,
    createdAt: existing?.fields?.createdAt ?? now,
    updatedAt: now,
  });
}

/** Uniform profile/lab writer for the Admin SDK and REST paths. */
function createStore(app) {
  if (USING_REST_FIRESTORE) {
    const store = new RestFirestore(PROJECT_ID, ACCESS_TOKEN);
    return {
      async upsertLab(lab) {
        await ensureLabRest(store, lab);
      },
      async upsertProfile(uid, account) {
        await upsertProfileRest(store, uid, account);
      },
      async readProfile(uid) {
        const doc = await store.get(`users/${uid}`);
        return {
          role: doc?.fields?.role?.stringValue ?? '(missing)',
          status: doc?.fields?.status?.stringValue ?? '(missing)',
        };
      },
    };
  }

  const db = getFirestore(app);
  return {
    async upsertLab(lab) {
      await ensureLab(db, lab);
    },
    async upsertProfile(uid, account) {
      await upsertProfile(db, uid, account);
    },
    async readProfile(uid) {
      const doc = await db.doc(`users/${uid}`).get();
      return {
        role: doc.get('role') ?? '(missing)',
        status: doc.get('status') ?? '(missing)',
      };
    },
  };
}

async function main() {
  console.log(`LabWatch demo seed · project ${PROJECT_ID}`);
  if (USING_EMULATORS) {
    console.log('Using Firebase emulators (no production data will change).');
  }
  if (USING_REST_FIRESTORE) {
    console.log(
      'Using the Firebase CLI access token (Auth via Admin SDK, Firestore ' +
        'via REST).',
    );
  }

  const app = buildApp();
  const auth = getAuth(app);
  const store = createStore(app);

  await store.upsertLab(DEMO_LAB);

  const rows = [];
  for (const account of DEMO_ACCOUNTS) {
    const { uid, created } = await ensureAuthUser(auth, account);
    await store.upsertProfile(uid, account);

    const profile = await store.readProfile(uid);
    rows.push({
      email: account.email,
      role: profile.role,
      status: profile.status,
      verified: true,
      action: created
        ? 'created with demo password'
        : 'existing, password unchanged',
      uid,
    });
  }

  console.table(rows);
  console.log('\nDemo accounts are ready. Email verification is already set.');
  console.log('Original demo passwords:');
  for (const account of DEMO_ACCOUNTS) {
    console.log(`  ${account.email}  ${account.password}`);
  }
  console.log(
    '\nIf an account already existed, its password was left unchanged; use the',
  );
  console.log(
    'password you set, or reset it from the Firebase Console. Never use these',
  );
  console.log('demo passwords outside a development project.');
}

main().catch((error) => {
  console.error('\nDemo seed failed.');
  console.error(error.message);

  if (
    !USING_EMULATORS &&
    /credential|default credentials|Could not load the default/i.test(
      error.message,
    )
  ) {
    console.error('\nProvide a service account:');
    console.error('  PowerShell:');
    console.error(
      '    $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\\path\\to\\service-account.json"',
    );
    console.error('  or run:  gcloud auth application-default login');
    console.error(
      '  or set FIREBASE_ACCESS_TOKEN to a short-lived OAuth token from a ' +
        'trusted CLI session',
    );
    console.error('\nOr point at the emulators:');
    console.error('    $env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"');
    console.error('    $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"');
  }

  process.exitCode = 1;
});
