import assert from 'node:assert/strict';
import test from 'node:test';
import { parseAppleNotification } from '../src/apple-notifications.js';

function fakeJws(payload) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({ alg: 'ES256', kid: 'test' })}.${encode(payload)}.signature`;
}

const productMap = new Map([
  ['1', 'com.kunqiong.remotelink.member.monthly'],
]);

test('Apple notification only yields a mapped transaction lookup instruction', () => {
  const notification = parseAppleNotification({
    signedPayload: fakeJws({
      notificationType: 'DID_RENEW',
      data: {
        environment: 'Sandbox',
        signedTransactionInfo: fakeJws({
          transactionId: '1000000123456789',
          originalTransactionId: '1000000123456000',
          productId: 'com.kunqiong.remotelink.member.monthly',
        }),
      },
    }),
  }, productMap);

  assert.deepEqual(notification, {
    notificationType: 'DID_RENEW',
    transactionId: '1000000123456789',
    originalTransactionId: '1000000123456000',
    productId: 'com.kunqiong.remotelink.member.monthly',
    packageId: '1',
    environment: 'sandbox',
  });
});

test('Apple notification ignores transactions outside configured membership products', () => {
  const notification = parseAppleNotification({
    signedPayload: fakeJws({
      data: {
        signedTransactionInfo: fakeJws({
          transactionId: '1000000123456789',
          originalTransactionId: '1000000123456000',
          productId: 'com.kunqiong.remotelink.other',
        }),
      },
    }),
  }, productMap);

  assert.equal(notification, null);
});

test('Apple notification ignores events without a transaction', () => {
  const notification = parseAppleNotification({
    signedPayload: fakeJws({ notificationType: 'DID_CHANGE_RENEWAL_STATUS', data: {} }),
  }, productMap);

  assert.equal(notification, null);
});
