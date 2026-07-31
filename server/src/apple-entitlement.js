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

function addMembershipDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function latestMembershipDate(...values) {
  return values
    .map(parseMembershipDate)
    .filter(Boolean)
    .sort((a, b) => b.getTime() - a.getTime())[0] || null;
}

function formatLatestMembershipDate(...values) {
  const latest = latestMembershipDate(...values);
  return latest ? formatMembershipDate(latest) : '';
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
  if (existingTransaction) {
    return formatLatestMembershipDate(
      existingOrderExpireAt,
      transaction?.expiresAt,
      currentExpireAt,
    ) || formatMembershipDate(parseMembershipDate(now) || new Date());
  }

  const base = latestMembershipDate(currentExpireAt, now) || now;
  const packageExpireAt = packageDays > 0
    ? addMembershipDays(base, Math.max(1, packageDays))
    : null;
  const resolved = latestMembershipDate(packageExpireAt, transaction?.expiresAt, now);
  return formatMembershipDate(resolved || now);
}
