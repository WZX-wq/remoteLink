import assert from 'node:assert/strict';
import test from 'node:test';
import { privacyPolicyPage } from '../src/privacy-policy.js';

test('uses generic membership disclosures unless the platform is explicitly iOS', () => {
  for (const platform of [undefined, 'android', 'Android', 'unknown']) {
    const policy = privacyPolicyPage(platform);

    assert.match(policy, /Membership and payments/);
    assert.doesNotMatch(policy, /Apple|App Store|StoreKit/i);
  }
});

test('retains Apple membership disclosures for iOS', () => {
  const policy = privacyPolicyPage('ios');

  assert.match(policy, /App Store 版本/);
  assert.match(policy, /Apple 订阅/);
  assert.match(policy, /Apple In-App Purchase/);
});
