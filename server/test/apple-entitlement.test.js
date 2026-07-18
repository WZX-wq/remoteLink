import assert from 'node:assert/strict';
import test from 'node:test';
import { claimAppleSubscriptionOwner } from '../src/apple-entitlement.js';

function ownerConnection() {
  const owners = new Map();
  return {
    async execute(query, values) {
      if (query.includes('INSERT INTO kq_apple_subscription_owners')) {
        const [originalTransactionId, userId] = values;
        if (!owners.has(originalTransactionId)) owners.set(originalTransactionId, userId);
        return [{ affectedRows: 1 }];
      }
      if (query.includes('SELECT user_id')) {
        const [originalTransactionId] = values;
        const userId = owners.get(originalTransactionId);
        return [userId == null ? [] : [{ user_id: userId }]];
      }
      throw new Error('unexpected query');
    },
  };
}

test('binds the first verified Apple subscription to its account', async () => {
  const connection = ownerConnection();
  await claimAppleSubscriptionOwner(connection, {
    originalTransactionId: '1000000123456789',
    userId: 101,
  });
  await claimAppleSubscriptionOwner(connection, {
    originalTransactionId: '1000000123456789',
    userId: 101,
  });
});

test('rejects a later renewal transaction when its Apple subscription belongs to another account', async () => {
  const connection = ownerConnection();
  await claimAppleSubscriptionOwner(connection, {
    originalTransactionId: '1000000123456789',
    userId: 101,
  });

  await assert.rejects(
    () =>
      claimAppleSubscriptionOwner(connection, {
        originalTransactionId: '1000000123456789',
        userId: 202,
      }),
    (error) => error.statusCode === 409,
  );
});
