import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import test from 'node:test';
import {
  buildAlipayAppPayOrderInfo,
  signAlipayParams,
  verifyAlipayApiResponseSignature,
  verifyAlipaySignature,
} from '../src/alipay.js';

function createTestKeys() {
  const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicExponent: 0x10001,
  });
  return {
    privateKey: privateKey.export({ type: 'pkcs8', format: 'pem' }),
    publicKey: publicKey.export({ type: 'spki', format: 'pem' }),
  };
}

function verifyRawContent(content, sign, publicKey) {
  return crypto
    .createVerify('RSA-SHA256')
    .update(content, 'utf8')
    .end()
    .verify(publicKey, sign, 'base64');
}

test('builds a signed Alipay App Pay order string for the Android SDK', () => {
  const keys = createTestKeys();
  const orderInfo = buildAlipayAppPayOrderInfo({
    appId: '2021006163671041',
    privateKey: keys.privateKey,
    notifyUrl: 'https://api.example.test/alipay/notify',
    outTradeNo: 'KQORDER123',
    totalAmount: 9.9,
    subject: 'Kunqiong Remote Desktop VIP',
    timestamp: '2026-06-23 10:11:12',
  });

  const params = Object.fromEntries(new URLSearchParams(orderInfo));
  assert.equal(params.app_id, '2021006163671041');
  assert.equal(params.method, 'alipay.trade.app.pay');
  assert.equal(params.charset, 'utf-8');
  assert.equal(params.sign_type, 'RSA2');
  assert.equal(params.timestamp, '2026-06-23 10:11:12');
  assert.equal(params.version, '1.0');
  assert.equal(params.notify_url, 'https://api.example.test/alipay/notify');
  assert.equal(params.format, undefined);
  assert.ok(params.sign);

  const bizContent = JSON.parse(params.biz_content);
  assert.equal(bizContent.out_trade_no, 'KQORDER123');
  assert.equal(bizContent.total_amount, '9.90');
  assert.equal(bizContent.subject, 'Kunqiong Remote Desktop VIP');
  assert.equal(bizContent.product_code, 'QUICK_MSECURITY_PAY');

  const requestSignContent = [
    `app_id=${params.app_id}`,
    `biz_content=${params.biz_content}`,
    `charset=${params.charset}`,
    `method=${params.method}`,
    `notify_url=${params.notify_url}`,
    `sign_type=${params.sign_type}`,
    `timestamp=${params.timestamp}`,
    `version=${params.version}`,
  ].join('&');
  assert.equal(verifyRawContent(requestSignContent, params.sign, keys.publicKey), true);
  assert.equal(
    verifyRawContent(
      requestSignContent.replace('sign_type=RSA2&', ''),
      params.sign,
      keys.publicKey,
    ),
    false,
  );
});

test('signs and verifies flat Alipay notify payloads', () => {
  const keys = createTestKeys();
  const payload = {
    app_id: '2021006163671041',
    out_trade_no: 'KQORDER123',
    trade_status: 'TRADE_SUCCESS',
    total_amount: '9.90',
    sign_type: 'RSA2',
  };
  const sign = signAlipayParams(payload, keys.privateKey, {
    includeSignType: false,
  });

  assert.equal(
    verifyAlipaySignature({ ...payload, sign }, keys.publicKey, {
      includeSignType: false,
    }),
    true,
  );
  assert.equal(
    verifyAlipaySignature(
      { ...payload, total_amount: '8.90', sign },
      keys.publicKey,
      { includeSignType: false },
    ),
    false,
  );
});

test('verifies signed Alipay API JSON responses', () => {
  const keys = createTestKeys();
  const responseValue =
    '{"code":"10000","msg":"Success","out_trade_no":"KQORDER123","trade_status":"TRADE_SUCCESS"}';
  const sign = crypto
    .createSign('RSA-SHA256')
    .update(responseValue, 'utf8')
    .end()
    .sign(keys.privateKey, 'base64');
  const response = `{"alipay_trade_query_response":${responseValue},"sign":"${sign}"}`;

  assert.equal(
    verifyAlipayApiResponseSignature(response, keys.publicKey),
    true,
  );
  assert.equal(
    verifyAlipayApiResponseSignature(
      response.replace('TRADE_SUCCESS', 'WAIT_BUYER_PAY'),
      keys.publicKey,
    ),
    false,
  );
});
