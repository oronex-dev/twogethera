import test from 'node:test';
import assert from 'node:assert/strict';

import {
  allowedOriginsForEnvironment,
  validateProjectTarget,
} from './project_target.mjs';

const expected = 'projectref1234567890';

test('development functions accept only local HTTP Supabase endpoints', () => {
  for (const url of [
    'http://127.0.0.1:54321',
    'http://localhost:54321',
    'http://kong:8000',
  ]) {
    assert.doesNotThrow(() => validateProjectTarget(url, 'development', ''));
  }
  assert.throws(
    () => validateProjectTarget('https://projectref1234567890.supabase.co', 'development', ''),
    /only local Supabase/,
  );
});

test('hosted functions require HTTPS and the exact approved project reference', () => {
  assert.doesNotThrow(() =>
    validateProjectTarget(`https://${expected}.supabase.co`, 'staging', expected),
  );
  assert.throws(
    () => validateProjectTarget('https://anotherref1234567890.supabase.co', 'staging', expected),
    /does not match/,
  );
  assert.throws(
    () => validateProjectTarget('http://127.0.0.1:54321', 'production', expected),
    /does not match/,
  );
  assert.throws(
    () => validateProjectTarget(`https://${expected}.supabase.co`, 'production', ''),
    /missing or invalid/,
  );
});

test('localhost CORS origin is added only in local development', () => {
  assert.equal(
    allowedOriginsForEnvironment('https://twogethera.vercel.app', 'development').has(
      'http://127.0.0.1:8081',
    ),
    true,
  );
  for (const environment of ['staging', 'production']) {
    assert.equal(
      allowedOriginsForEnvironment('https://twogethera.vercel.app', environment).has(
        'http://127.0.0.1:8081',
      ),
      false,
    );
  }
});
