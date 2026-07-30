import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import test from 'node:test';
import {
  AppleIapError,
  buildAppStoreServerApiToken,
  fetchAndValidateAppleTransaction,
  parseAppleProductMap,
  resolveAppleTransactionId,
} from '../src/apple-iap.js';
import { appleIapReadiness } from '../src/apple-iap-readiness.js';

function base64UrlJson(value) {
  return Buffer.from(JSON.stringify(value))
    .toString('base64url');
}

function fakeJws(payload) {
  return `${base64UrlJson({ alg: 'ES256', kid: 'test' })}.${base64UrlJson(payload)}.signature`;
}

function appleConfig(overrides = {}) {
  const { privateKey } = crypto.generateKeyPairSync('ec', {
    namedCurve: 'prime256v1',
  });
  return {
    bundleId: 'com.kunqiong.remotelink',
    issuerId: 'issuer-id',
    keyId: 'key-id',
    privateKey: privateKey.export({ type: 'pkcs8', format: 'pem' }),
    environment: 'sandbox',
    ...overrides,
  };
}

test('parses a package-to-product map without accepting empty product IDs', () => {
  assert.deepEqual(
    parseAppleProductMap(
      '{"1":"com.kunqiong.remotelink.member.monthly","2":"com.kunqiong.remotelink.member.quarterly"}',
    ),
    new Map([
      ['1', 'com.kunqiong.remotelink.member.monthly'],
      ['2', 'com.kunqiong.remotelink.member.quarterly'],
    ]),
  );
  assert.throws(
    () => parseAppleProductMap('{"1":""}'),
    /empty product ID/i,
  );
});

test('accepts an Apple private key provided through an escaped CI environment value', () => {
  const config = appleConfig();
  const token = buildAppStoreServerApiToken({
    ...config,
    privateKey: config.privateKey.replace(/\n/g, '\\n'),
  });

  assert.match(token, /^ey/);
});

test('uses the StoreKit transaction ID only when it matches signed transaction data', () => {
  const signed = fakeJws({ transactionId: '1000000123456789' });
  assert.equal(
    resolveAppleTransactionId({
      transactionId: '1000000123456789',
      signedTransaction: signed,
    }),
    '1000000123456789',
  );
  assert.throws(
    () =>
      resolveAppleTransactionId({
        transactionId: '1000000123456789',
        signedTransaction: fakeJws({ transactionId: '1000000999999999' }),
      }),
    /does not match/i,
  );
});

test('verifies a StoreKit transaction against the Apple sandbox API response', async () => {
  const transactionId = '1000000123456789';
  let receivedUrl = '';
  let receivedAuthorization = '';
  const transaction = await fetchAndValidateAppleTransaction({
    transactionId,
    expectedProductId: 'com.kunqiong.remotelink.member.monthly',
    config: appleConfig(),
    fetchImpl: async (url, options) => {
      receivedUrl = String(url);
      receivedAuthorization = String(options.headers.Authorization || '');
      return new Response(
        JSON.stringify({
          signedTransactionInfo: fakeJws({
            transactionId,
            originalTransactionId: transactionId,
            productId: 'com.kunqiong.remotelink.member.monthly',
            bundleId: 'com.kunqiong.remotelink',
            environment: 'Sandbox',
            expiresDate: '1780000000000',
          }),
        }),
        { status: 200, headers: { 'content-type': 'application/json' } },
      );
    },
  });

  assert.match(receivedUrl, /api\.storekit-sandbox\.itunes\.apple\.com\/inApps\/v1\/transactions\/1000000123456789$/);
  assert.match(receivedAuthorization, /^Bearer ey/);
  assert.equal(transaction.transactionId, transactionId);
  assert.equal(transaction.environment, 'Sandbox');
  assert.equal(transaction.expiresAt, '2026-05-28 20:26:40');
});

test('routes a TestFlight sandbox transaction to Apple sandbox when server defaults to production', async () => {
  const transactionId = '1000000123456790';
  const signedTransaction = fakeJws({
    transactionId,
    environment: 'Sandbox',
  });
  const receivedUrls = [];
  const transaction = await fetchAndValidateAppleTransaction({
    transactionId,
    signedTransaction,
    expectedProductId: 'com.kunqiong.remotelink.member.monthly',
    config: appleConfig({ environment: 'production' }),
    fetchImpl: async (url) => {
      receivedUrls.push(String(url));
      return new Response(
        JSON.stringify({
          signedTransactionInfo: fakeJws({
            transactionId,
            originalTransactionId: transactionId,
            productId: 'com.kunqiong.remotelink.member.monthly',
            bundleId: 'com.kunqiong.remotelink',
            environment: 'Sandbox',
          }),
        }),
        { status: 200, headers: { 'content-type': 'application/json' } },
      );
    },
  });

  assert.equal(transaction.environment, 'Sandbox');
  assert.deepEqual(receivedUrls, [
    'https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions/1000000123456790',
  ]);
});

test('times out an unresponsive Apple verification request', async () => {
  await assert.rejects(
    () =>
      fetchAndValidateAppleTransaction({
        transactionId: '1000000123456791',
        expectedProductId: 'com.kunqiong.remotelink.member.monthly',
        config: appleConfig(),
        timeoutMs: 5,
        fetchImpl: (_url, options) =>
          new Promise((_resolve, reject) => {
            options.signal.addEventListener('abort', () =>
              reject(Object.assign(new Error('aborted'), { name: 'AbortError' })),
            );
          }),
      }),
    (error) =>
      error instanceof AppleIapError &&
      error.statusCode === 504 &&
      error.reason === 'apple_upstream_timeout',
  );
});

test('times out while reading a stalled Apple verification response', async () => {
  await assert.rejects(
    () =>
      fetchAndValidateAppleTransaction({
        transactionId: '1000000123456792',
        expectedProductId: 'com.kunqiong.remotelink.member.monthly',
        config: appleConfig(),
        timeoutMs: 5,
        fetchImpl: async (_url, options) => ({
          ok: true,
          json: () =>
            new Promise((_resolve, reject) => {
              options.signal.addEventListener('abort', () =>
                reject(Object.assign(new Error('aborted'), { name: 'AbortError' })),
              );
            }),
        }),
      }),
    (error) =>
      error instanceof AppleIapError &&
      error.statusCode === 504 &&
      error.reason === 'apple_upstream_timeout',
  );
});

test('retains an Apple upstream status without exposing its response body', async () => {
  await assert.rejects(
    () =>
      fetchAndValidateAppleTransaction({
        transactionId: '1000000123456793',
        expectedProductId: 'com.kunqiong.remotelink.member.monthly',
        config: appleConfig(),
        fetchImpl: async () => new Response('{}', { status: 401 }),
      }),
    (error) =>
      error instanceof AppleIapError &&
      error.statusCode === 502 &&
      error.reason === 'apple_upstream_rejected' &&
      error.upstreamStatus === 401,
  );
});

test('reports only non-sensitive Apple IAP readiness fields', () => {
  const result = appleIapReadiness({
    productsJson: '{"1":"com.kunqiong.remotelink.member.monthly"}',
    bundleId: 'com.kunqiong.remotelink',
    issuerId: 'issuer-secret-value',
    keyId: 'key-secret-value',
    privateKey: 'private-key-secret-value',
    privateKeySource: 'inline',
    environment: 'production',
  });

  assert.deepEqual(result, {
    products_configured: true,
    bundle_id_configured: true,
    issuer_id_configured: true,
    key_id_configured: true,
    private_key_configured: true,
    private_key_source: 'inline',
    private_key_path_readable: null,
    environment: 'production',
    ready: true,
  });
  assert.equal(JSON.stringify(result).includes('secret-value'), false);
});

test('marks an unreadable file-backed Apple key as not ready', () => {
  const result = appleIapReadiness(
    {
      productsJson: '{"1":"com.kunqiong.remotelink.member.monthly"}',
      bundleId: 'com.kunqiong.remotelink',
      issuerId: 'issuer',
      keyId: 'key',
      privateKey: '',
      privateKeyPath: '/app/data/AuthKey.p8',
      privateKeySource: 'path',
      environment: 'sandbox',
    },
    { constants: { R_OK: 4 }, accessSync: () => { throw new Error('missing'); } },
  );

  assert.equal(result.private_key_path_readable, false);
  assert.equal(result.ready, false);
});

test('rejects an Apple transaction whose product does not match the selected package', async () => {
  await assert.rejects(
    () =>
      fetchAndValidateAppleTransaction({
        transactionId: '1000000123456789',
        expectedProductId: 'com.kunqiong.remotelink.member.monthly',
        config: appleConfig(),
        fetchImpl: async () =>
          new Response(
            JSON.stringify({
              signedTransactionInfo: fakeJws({
                transactionId: '1000000123456789',
                productId: 'com.kunqiong.remotelink.member.quarterly',
                bundleId: 'com.kunqiong.remotelink',
                environment: 'Sandbox',
              }),
            }),
            { status: 200, headers: { 'content-type': 'application/json' } },
          ),
      }),
    (error) => error instanceof AppleIapError && error.statusCode === 400,
  );
});

test('returns a revoked transaction only for a lifecycle notification handler', async () => {
  const transaction = await fetchAndValidateAppleTransaction({
    transactionId: '1000000123456789',
    expectedProductId: 'com.kunqiong.remotelink.member.monthly',
    config: appleConfig(),
    allowRevoked: true,
    fetchImpl: async () => new Response(JSON.stringify({
      signedTransactionInfo: fakeJws({
        transactionId: '1000000123456789',
        originalTransactionId: '1000000123456000',
        productId: 'com.kunqiong.remotelink.member.monthly',
        bundleId: 'com.kunqiong.remotelink',
        environment: 'Sandbox',
        revocationDate: '1780000000000',
      }),
    }), { status: 200, headers: { 'content-type': 'application/json' } }),
  });

  assert.equal(transaction.revoked, true);
  assert.equal(transaction.revocationDate, '2026-05-28 20:26:40');
});
