import { AppleIapError } from './apple-iap.js';

function parseJwsPayload(value) {
  const parts = String(value || '').trim().split('.');
  if (parts.length !== 3 || !parts[1]) {
    throw new AppleIapError('Apple notification data is invalid.');
  }
  try {
    const parsed = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('not an object');
    }
    return parsed;
  } catch (_) {
    throw new AppleIapError('Apple notification data is invalid.');
  }
}

function normalizeEnvironment(value) {
  const environment = String(value || '').trim().toLowerCase();
  if (environment === 'sandbox') return 'sandbox';
  if (environment === 'production') return 'production';
  return '';
}

function packageForProduct(productMap, productId) {
  for (const [packageId, configuredProductId] of productMap.entries()) {
    if (configuredProductId === productId) return packageId;
  }
  return null;
}

/**
 * Extracts a transaction lookup instruction from an Apple notification.
 *
 * The JWS is not trusted as an entitlement. It only supplies a transaction ID;
 * callers must fetch that transaction again through the App Store Server API
 * before touching local membership state.
 */
export function parseAppleNotification(payload, productMap) {
  if (!(productMap instanceof Map)) {
    throw new AppleIapError('Apple product mapping is invalid.', 503);
  }
  const envelope = parseJwsPayload(payload?.signedPayload);
  const data = envelope.data;
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    return null;
  }
  const signedTransaction = String(data.signedTransactionInfo || '').trim();
  if (!signedTransaction) {
    return null;
  }
  const transaction = parseJwsPayload(signedTransaction);
  const transactionId = String(transaction.transactionId || '').trim();
  const originalTransactionId = String(
    transaction.originalTransactionId || transactionId,
  ).trim();
  const productId = String(transaction.productId || '').trim();
  if (!/^[A-Za-z0-9._-]{6,128}$/.test(transactionId) ||
      !/^[A-Za-z0-9._-]{6,128}$/.test(originalTransactionId) ||
      !productId) {
    throw new AppleIapError('Apple notification transaction data is invalid.');
  }
  const packageId = packageForProduct(productMap, productId);
  if (!packageId) {
    return null;
  }
  return {
    notificationType: String(envelope.notificationType || '').trim().toUpperCase(),
    transactionId,
    originalTransactionId,
    productId,
    packageId,
    environment: normalizeEnvironment(data.environment || transaction.environment),
  };
}
