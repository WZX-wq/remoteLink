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
