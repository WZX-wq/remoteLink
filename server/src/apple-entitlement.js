export async function claimAppleSubscriptionOwner(
  connection,
  { originalTransactionId, userId },
) {
  await connection.execute(
    `
      INSERT INTO kq_apple_subscription_owners (
        original_transaction_id, user_id
      )
      VALUES (?, ?)
      ON DUPLICATE KEY UPDATE updated_at = NOW()
    `,
    [originalTransactionId, userId],
  );
  const [rows] = await connection.execute(
    `
      SELECT user_id
      FROM kq_apple_subscription_owners
      WHERE original_transaction_id = ?
      LIMIT 1
      FOR UPDATE
    `,
    [originalTransactionId],
  );
  if (!rows[0]) {
    throw Object.assign(new Error('Apple subscription ownership could not be recorded.'), {
      statusCode: 500,
    });
  }
  if (Number(rows[0].user_id) !== Number(userId)) {
    throw Object.assign(
      new Error('This Apple subscription has already been used by another account.'),
      { statusCode: 409 },
    );
  }
}

function parseMembershipDate(value) {
  if (!value) return null;
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }
  const raw = String(value).trim();
  if (!raw) return null;
  const normalized = raw.includes('T') ? raw : `${raw.replace(' ', 'T')}Z`;
  const parsed = new Date(normalized);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function formatMembershipDate(date) {
  const pad = (value) => String(value).padStart(2, '0');
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())} ${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}:${pad(date.getUTCSeconds())}`;
}

export function formatAppleMembershipExpiryForClient(value) {
  const raw = String(value || '').trim();
  if (!raw || raw.toLowerCase() === 'unlimited' || raw === '9999-12-31 23:59:59') {
    return raw;
  }
  const parsed = parseMembershipDate(raw);
  return parsed ? parsed.toISOString().replace('.000Z', 'Z') : raw;
}

function addMembershipDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

export function isRetryableAppleTransactionError(error) {
  return error?.code === 'ER_LOCK_DEADLOCK' ||
    Number(error?.errno) === 1213 ||
    error?.sqlState === '40001';
}

export async function withAppleTransactionRetry(
  operation,
  { maxAttempts = 3, delayMs = 50, onRetry = null } = {},
) {
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      return await operation();
    } catch (error) {
      if (!isRetryableAppleTransactionError(error) || attempt === maxAttempts) {
        throw error;
      }
      if (onRetry) onRetry(error, attempt);
      await new Promise((resolve) => setTimeout(resolve, delayMs * attempt));
    }
  }
  throw new Error('Apple transaction retry exhausted.');
}

export function resolveAppleProjectMembershipExpiry({
  memberPackage,
  transaction,
  currentExpireAt = null,
  existingOrderExpireAt = null,
  existingTransaction = null,
  now = new Date(),
  lifetimeProductId = '',
}) {
  const packageDays = Number(memberPackage?.days || 0);
  const productId = String(transaction?.productId || '').trim();
  const isLifetime =
    packageDays >= 999999 || (lifetimeProductId && productId === lifetimeProductId);
  if (isLifetime) {
    return '9999-12-31 23:59:59';
  }
  const appleExpireAt = parseMembershipDate(transaction?.expiresAt);
  if (appleExpireAt) return formatMembershipDate(appleExpireAt);

  const storedExpireAt = parseMembershipDate(existingOrderExpireAt) ||
    parseMembershipDate(currentExpireAt);
  if (storedExpireAt) return formatMembershipDate(storedExpireAt);

  const base = parseMembershipDate(now) || new Date();
  return formatMembershipDate(
    addMembershipDays(base, Math.max(1, packageDays)),
  );
}
