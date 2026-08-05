import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import {
  claimAppleSubscriptionOwner,
  formatAppleMembershipExpiryForClient,
  isRetryableAppleTransactionError,
  resolveAppleProjectMembershipExpiry,
  withAppleTransactionRetry,
} from '../src/apple-entitlement.js';

test('formats Apple membership expiry with an explicit UTC offset for clients', () => {
  assert.equal(
    formatAppleMembershipExpiryForClient('2026-08-04 09:43:42'),
    '2026-08-04T09:43:42Z',
  );
  assert.equal(
    formatAppleMembershipExpiryForClient('9999-12-31 23:59:59'),
    '9999-12-31 23:59:59',
  );
});

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

test('Apple subscription expiry comes from Apple instead of extending stale local state', () => {
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
    '2026-08-01 00:00:00',
  );
});

test('Apple restore uses the current Apple expiry instead of stale order expiry', () => {
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
    '2026-08-01 00:00:00',
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
    '2026-08-01 00:00:00',
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

test('Apple membership claims the subscription owner before locking its transaction row', () => {
  const source = fs.readFileSync(new URL('../src/index.js', import.meta.url), 'utf8');
  const grantStart = source.indexOf('async function grantAppleMembership');
  const claim = source.indexOf('await claimAppleSubscriptionOwner', grantStart);
  const transactionLock = source.indexOf(
    "SELECT * FROM kq_apple_transactions WHERE transaction_id = ? FOR UPDATE",
    grantStart,
  );

  assert.ok(grantStart >= 0);
  assert.ok(claim >= 0 && transactionLock >= 0);
  assert.ok(claim < transactionLock);
});

test('Apple transaction retry retries deadlocks and stops on success', async () => {
  let attempts = 0;
  const result = await withAppleTransactionRetry(
    async () => {
      attempts += 1;
      if (attempts < 3) {
        throw Object.assign(new Error('deadlock'), {
          code: 'ER_LOCK_DEADLOCK',
          errno: 1213,
          sqlState: '40001',
        });
      }
      return 'ok';
    },
    { delayMs: 0 },
  );

  assert.equal(result, 'ok');
  assert.equal(attempts, 3);
  assert.equal(isRetryableAppleTransactionError({ errno: 1213 }), true);
  assert.equal(isRetryableAppleTransactionError({ code: 'ER_BAD_FIELD_ERROR' }), false);
});

test('Apple verification returns the final entitlement across all active orders', () => {
  const source = fs.readFileSync(new URL('../src/index.js', import.meta.url), 'utf8');
  const grantStart = source.indexOf('async function grantAppleMembershipOnce');
  const grantEnd = source.indexOf('async function grantAppleMembership(args)', grantStart);
  const grantSource = source.slice(grantStart, grantEnd);
  const membershipOrderWrite = grantSource.indexOf(
    'INSERT INTO kq_member_orders',
  );
  const finalEntitlementRead = grantSource.indexOf('const effectiveOrder = await');

  assert.ok(membershipOrderWrite >= 0);
  assert.ok(finalEntitlementRead > membershipOrderWrite);
  assert.match(grantSource, /latestPaidProjectMemberOrder\(/);
  assert.match(grantSource, /return \{ expireAt: effectiveExpireAt, memberActive \}/);
});

test('Apple membership expiry queries compare UTC timestamps', () => {
  const source = fs.readFileSync(new URL('../src/index.js', import.meta.url), 'utf8');
  const helperStart = source.indexOf('async function latestPaidProjectMemberOrder');
  const helperEnd = source.indexOf('async function markProjectMemberOrderPaid', helperStart);
  const helperSource = source.slice(helperStart, helperEnd);

  assert.ok(helperStart >= 0 && helperEnd > helperStart);
  assert.match(helperSource, /expire_at > UTC_TIMESTAMP\(\)/);
  assert.doesNotMatch(helperSource, /expire_at > NOW\(\)/);
});
