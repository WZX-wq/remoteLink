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
