import assert from 'node:assert/strict';
import test from 'node:test';
import {
  claimAppleSubscriptionOwner,
  resolveAppleProjectMembershipExpiry,
} from '../src/apple-entitlement.js';

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

test('Apple upgrade grants the selected package duration from the current entitlement', () => {
  assert.equal(
    resolveAppleProjectMembershipExpiry({
      memberPackage: { days: 90 },
      transaction: {
        productId: 'com.kunqiong.remotelink.member.quarterly',
        expiresAt: '2026-08-01 00:00:00',
      },
      currentExpireAt: '2026-08-10 12:00:00',
      existingTransaction: null,
      now: new Date('2026-07-31T00:00:00Z'),
      lifetimeProductId: 'com.kunqiong.remotelink.member.lifetime',
    }),
    '2026-11-08 12:00:00',
  );
});

test('Apple restore of an already verified transaction does not extend again', () => {
  assert.equal(
    resolveAppleProjectMembershipExpiry({
      memberPackage: { days: 90 },
      transaction: {
        productId: 'com.kunqiong.remotelink.member.quarterly',
        expiresAt: '2026-08-01 00:00:00',
      },
      currentExpireAt: '2026-08-10 12:00:00',
      existingOrderExpireAt: '2026-11-08 12:00:00',
      existingTransaction: { transaction_id: '1000000123456789' },
      now: new Date('2026-07-31T00:00:00Z'),
      lifetimeProductId: 'com.kunqiong.remotelink.member.lifetime',
    }),
    '2026-11-08 12:00:00',
  );
});

test('Apple restore falls back safely when a stored order expiry is invalid', () => {
  assert.equal(
    resolveAppleProjectMembershipExpiry({
      memberPackage: { days: 90 },
      transaction: {
        productId: 'com.kunqiong.remotelink.member.quarterly',
        expiresAt: '2026-08-01 00:00:00',
      },
      currentExpireAt: '2026-08-10 12:00:00',
      existingOrderExpireAt: 'not-a-date',
      existingTransaction: { transaction_id: '1000000123456789' },
      now: new Date('2026-07-31T00:00:00Z'),
      lifetimeProductId: 'com.kunqiong.remotelink.member.lifetime',
    }),
    '2026-08-10 12:00:00',
  );
});

test('Apple lifetime restore keeps the lifetime expiry marker', () => {
  assert.equal(
    resolveAppleProjectMembershipExpiry({
      memberPackage: { days: 999999 },
      transaction: {
        productId: 'com.kunqiong.remotelink.member.lifetime',
      },
      existingTransaction: { transaction_id: '1000000123456790' },
      now: new Date('2026-07-31T00:00:00Z'),
      lifetimeProductId: 'com.kunqiong.remotelink.member.lifetime',
    }),
    '9999-12-31 23:59:59',
  );
});
