import crypto from 'node:crypto';

const APPLE_API_BASE_URLS = {
  sandbox: 'https://api.storekit-sandbox.itunes.apple.com',
  production: 'https://api.storekit.itunes.apple.com',
};

export class AppleIapError extends Error {
  constructor(message, statusCode = 400) {
    super(message);
    this.name = 'AppleIapError';
    this.statusCode = statusCode;
  }
}

function base64UrlJson(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

function parseJwsPayload(value) {
  const parts = String(value || '').trim().split('.');
  if (parts.length !== 3 || !parts[1]) {
    throw new AppleIapError('Apple transaction data is invalid.');
  }
  try {
    const parsed = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('not an object');
    }
    return parsed;
  } catch (_) {
    throw new AppleIapError('Apple transaction data is invalid.');
  }
}

function requiredString(value, name) {
  const normalized = String(value || '').trim();
  if (!normalized) {
    throw new AppleIapError(`${name} is not configured.`, 503);
  }
  return normalized;
}

function normalizePrivateKey(value) {
  return requiredString(value, 'KQ_APPLE_IAP_PRIVATE_KEY')
    .replace(/\r\n/g, '\n')
    .replace(/\\n/g, '\n');
}

function normalizeEnvironment(value) {
  const normalized = String(value || 'sandbox').trim().toLowerCase();
  if (normalized !== 'sandbox' && normalized !== 'production') {
    throw new AppleIapError('Apple purchase verification environment is invalid.', 503);
  }
  return normalized;
}

function normalizeAppleEnvironment(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === 'sandbox') return 'sandbox';
  if (normalized === 'production') return 'production';
  return '';
}

function mysqlDateTimeFromMillis(value) {
  const milliseconds = Number(value);
  if (!Number.isFinite(milliseconds) || milliseconds <= 0) return null;
  const date = new Date(milliseconds);
  if (Number.isNaN(date.getTime())) return null;
  const pad = (part) => String(part).padStart(2, '0');
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())} ${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}:${pad(date.getUTCSeconds())}`;
}

export function parseAppleProductMap(value) {
  let parsed;
  try {
    parsed = JSON.parse(String(value || '').trim());
  } catch (_) {
    throw new AppleIapError('Apple product mapping is invalid.', 503);
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new AppleIapError('Apple product mapping is invalid.', 503);
  }
  const result = new Map();
  for (const [rawPackageId, rawProductId] of Object.entries(parsed)) {
    const packageId = String(rawPackageId || '').trim();
    const productId = String(rawProductId || '').trim();
    if (!packageId) {
      throw new AppleIapError('Apple product mapping contains an empty package ID.', 503);
    }
    if (!productId) {
      throw new AppleIapError('Apple product mapping contains an empty product ID.', 503);
    }
    if ([...result.values()].includes(productId)) {
      throw new AppleIapError('Apple product mapping contains duplicate product IDs.', 503);
    }
    result.set(packageId, productId);
  }
  if (!result.size) {
    throw new AppleIapError('Apple product mapping is not configured.', 503);
  }
  return result;
}

export function resolveAppleTransactionId({ transactionId, signedTransaction }) {
  const directId = String(transactionId || '').trim();
  let signedId = '';
  if (String(signedTransaction || '').trim()) {
    signedId = String(parseJwsPayload(signedTransaction).transactionId || '').trim();
  }
  const resolved = directId || signedId;
  if (!/^[A-Za-z0-9._-]{6,128}$/.test(resolved)) {
    throw new AppleIapError('Apple transaction ID is invalid.');
  }
  if (directId && signedId && directId !== signedId) {
    throw new AppleIapError('Apple transaction ID does not match signed transaction data.');
  }
  return resolved;
}

export function buildAppStoreServerApiToken(config, now = new Date()) {
  const bundleId = requiredString(config?.bundleId, 'KQ_APPLE_IAP_BUNDLE_ID');
  const issuerId = requiredString(config?.issuerId, 'KQ_APPLE_IAP_ISSUER_ID');
  const keyId = requiredString(config?.keyId, 'KQ_APPLE_IAP_KEY_ID');
  const privateKey = normalizePrivateKey(config?.privateKey);
  const issuedAt = Math.floor(now.getTime() / 1000);
  const encodedHeader = base64UrlJson({ alg: 'ES256', kid: keyId, typ: 'JWT' });
  const encodedPayload = base64UrlJson({
    iss: issuerId,
    iat: issuedAt,
    exp: issuedAt + 300,
    aud: 'appstoreconnect-v1',
    bid: bundleId,
  });
  const signature = crypto
    .createSign('SHA256')
    .update(`${encodedHeader}.${encodedPayload}`, 'utf8')
    .end()
    .sign(privateKey)
    .toString('base64url');
  return `${encodedHeader}.${encodedPayload}.${signature}`;
}

export async function fetchAndValidateAppleTransaction({
  transactionId,
  expectedProductId,
  config,
  fetchImpl = fetch,
}) {
  const normalizedTransactionId = String(transactionId || '').trim();
  const normalizedProductId = String(expectedProductId || '').trim();
  if (!normalizedTransactionId || !normalizedProductId) {
    throw new AppleIapError('Apple transaction data is incomplete.');
  }
  const environment = normalizeEnvironment(config?.environment);
  const bundleId = requiredString(config?.bundleId, 'KQ_APPLE_IAP_BUNDLE_ID');
  const token = buildAppStoreServerApiToken(config);
  const apiBaseUrl = APPLE_API_BASE_URLS[environment];
  let response;
  try {
    response = await fetchImpl(
      `${apiBaseUrl}/inApps/v1/transactions/${encodeURIComponent(normalizedTransactionId)}`,
      {
        headers: {
          Accept: 'application/json',
          Authorization: `Bearer ${token}`,
        },
      },
    );
  } catch (_) {
    throw new AppleIapError('Unable to contact Apple purchase verification service.', 502);
  }

  let payload;
  try {
    payload = await response.json();
  } catch (_) {
    throw new AppleIapError('Apple purchase verification returned invalid data.', 502);
  }
  if (!response.ok) {
    throw new AppleIapError('Apple could not verify this purchase.', 502);
  }
  const claims = parseJwsPayload(payload?.signedTransactionInfo);
  const appleTransactionId = String(claims.transactionId || '').trim();
  if (appleTransactionId !== normalizedTransactionId) {
    throw new AppleIapError('Apple transaction verification did not match the requested transaction.', 400);
  }
  if (String(claims.productId || '').trim() !== normalizedProductId) {
    throw new AppleIapError('Apple transaction does not match this membership package.');
  }
  if (String(claims.bundleId || '').trim() !== bundleId) {
    throw new AppleIapError('Apple transaction belongs to a different app.', 400);
  }
  const appleEnvironment = normalizeAppleEnvironment(claims.environment);
  if (!appleEnvironment || appleEnvironment !== environment) {
    throw new AppleIapError('Apple transaction environment does not match this server.', 400);
  }
  if (claims.revocationDate) {
    throw new AppleIapError('Apple has revoked this purchase.', 409);
  }
  return {
    transactionId: appleTransactionId,
    originalTransactionId: String(claims.originalTransactionId || appleTransactionId),
    productId: normalizedProductId,
    bundleId,
    environment: String(claims.environment || ''),
    expiresAt: mysqlDateTimeFromMillis(claims.expiresDate),
    purchaseDate: mysqlDateTimeFromMillis(claims.purchaseDate),
    signedTransactionInfo: String(payload.signedTransactionInfo),
    claims,
  };
}
