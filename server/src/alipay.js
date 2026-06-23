import crypto from 'node:crypto';

const ALIPAY_CHARSET = 'UTF-8';
const ALIPAY_SIGN_TYPE = 'RSA2';
const ALIPAY_VERSION = '1.0';
const ALIPAY_APP_PAY_METHOD = 'alipay.trade.app.pay';
const ALIPAY_TRADE_QUERY_METHOD = 'alipay.trade.query';
const ALIPAY_APP_PAY_PRODUCT_CODE = 'QUICK_MSECURITY_PAY';

function cleanKeyText(value) {
  return String(value || '').replace(/\\n/g, '\n').trim();
}

function derFromBase64Body(value) {
  const body = cleanKeyText(value).replace(/\s+/g, '');
  if (!body) return null;
  if (!/^[A-Za-z0-9+/=]+$/.test(body)) return null;
  return Buffer.from(body, 'base64');
}

function privateKeyObject(value) {
  const text = cleanKeyText(value);
  if (!text) {
    throw new Error('Alipay private key is required');
  }
  if (text.includes('BEGIN')) {
    return crypto.createPrivateKey(text);
  }
  const der = derFromBase64Body(text);
  if (!der) {
    throw new Error('Alipay private key is not valid base64');
  }
  for (const type of ['pkcs8', 'pkcs1']) {
    try {
      return crypto.createPrivateKey({ key: der, format: 'der', type });
    } catch {
      // Try the next supported private-key container.
    }
  }
  throw new Error('Alipay private key format is not supported');
}

function publicKeyObject(value) {
  const text = cleanKeyText(value);
  if (!text) {
    throw new Error('Alipay public key is required');
  }
  if (text.includes('BEGIN')) {
    return crypto.createPublicKey(text);
  }
  const der = derFromBase64Body(text);
  if (!der) {
    throw new Error('Alipay public key is not valid base64');
  }
  return crypto.createPublicKey({ key: der, format: 'der', type: 'spki' });
}

function alipayParamValue(value) {
  if (value == null) return '';
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

function hasValue(value) {
  return value !== undefined && value !== null && String(value).trim() !== '';
}

export function alipaySignContent(params, options = {}) {
  const includeSignType = options.includeSignType !== false;
  return Object.entries(params || {})
    .filter(
      ([key, value]) =>
        key &&
        key !== 'sign' &&
        (includeSignType || key !== 'sign_type') &&
        hasValue(value),
    )
    .sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0))
    .map(([key, value]) => `${key}=${alipayParamValue(value)}`)
    .join('&');
}

export function signAlipayParams(params, privateKey, options = {}) {
  const content = alipaySignContent(params, options);
  return crypto
    .createSign('RSA-SHA256')
    .update(content, 'utf8')
    .end()
    .sign(privateKeyObject(privateKey), 'base64');
}

export function verifyAlipaySignature(params, publicKey, options = {}) {
  const sign = String(params?.sign || '').trim();
  if (!sign) return false;
  try {
    return crypto
      .createVerify('RSA-SHA256')
      .update(alipaySignContent(params, options), 'utf8')
      .end()
      .verify(publicKeyObject(publicKey), sign, 'base64');
  } catch {
    return false;
  }
}

export function formatAlipayTimestamp(value = new Date()) {
  if (typeof value === 'string') return value;
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error('Invalid Alipay timestamp');
  }
  const shanghai = new Date(date.getTime() + 8 * 60 * 60 * 1000);
  const pad = (part) => String(part).padStart(2, '0');
  return [
    `${shanghai.getUTCFullYear()}-${pad(shanghai.getUTCMonth() + 1)}-${pad(shanghai.getUTCDate())}`,
    `${pad(shanghai.getUTCHours())}:${pad(shanghai.getUTCMinutes())}:${pad(shanghai.getUTCSeconds())}`,
  ].join(' ');
}

export function formatAlipayAmount(value) {
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new Error('Alipay amount must be greater than 0');
  }
  return amount.toFixed(2);
}

export function serializeAlipayParams(params) {
  return Object.entries(params || {})
    .filter(([key, value]) => key && hasValue(value))
    .sort(([left], [right]) => left.localeCompare(right, 'en'))
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(alipayParamValue(value))}`)
    .join('&');
}

function buildSignedAlipayParams({
  appId,
  privateKey,
  method,
  bizContent,
  notifyUrl = '',
  timestamp = new Date(),
}) {
  if (!String(appId || '').trim()) {
    throw new Error('Alipay appId is required');
  }
  if (!String(method || '').trim()) {
    throw new Error('Alipay method is required');
  }
  const params = {
    app_id: String(appId).trim(),
    biz_content: JSON.stringify(bizContent || {}),
    charset: ALIPAY_CHARSET,
    format: 'json',
    method,
    sign_type: ALIPAY_SIGN_TYPE,
    timestamp: formatAlipayTimestamp(timestamp),
    version: ALIPAY_VERSION,
  };
  if (String(notifyUrl || '').trim()) {
    params.notify_url = String(notifyUrl).trim();
  }
  return {
    ...params,
    sign: signAlipayParams(params, privateKey),
  };
}

export function buildAlipayAppPayOrderInfo({
  appId,
  privateKey,
  notifyUrl = '',
  outTradeNo,
  totalAmount,
  subject,
  body = '',
  timestamp = new Date(),
}) {
  const bizContent = {
    out_trade_no: String(outTradeNo || '').trim(),
    product_code: ALIPAY_APP_PAY_PRODUCT_CODE,
    subject: String(subject || 'Kunqiong membership').trim().slice(0, 256),
    total_amount: formatAlipayAmount(totalAmount),
  };
  if (!bizContent.out_trade_no) {
    throw new Error('Alipay out_trade_no is required');
  }
  if (String(body || '').trim()) {
    bizContent.body = String(body).trim().slice(0, 128);
  }
  return serializeAlipayParams(buildSignedAlipayParams({
    appId,
    privateKey,
    method: ALIPAY_APP_PAY_METHOD,
    bizContent,
    notifyUrl,
    timestamp,
  }));
}

export function buildAlipayTradeQueryBody({
  appId,
  privateKey,
  outTradeNo,
  timestamp = new Date(),
}) {
  const outTradeNoText = String(outTradeNo || '').trim();
  if (!outTradeNoText) {
    throw new Error('Alipay out_trade_no is required');
  }
  return serializeAlipayParams(buildSignedAlipayParams({
    appId,
    privateKey,
    method: ALIPAY_TRADE_QUERY_METHOD,
    bizContent: { out_trade_no: outTradeNoText },
    timestamp,
  }));
}

function parseJsonResponse(response) {
  if (typeof response === 'string') {
    return JSON.parse(response);
  }
  return response || {};
}

function findRawJsonObjectEnd(text, start) {
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < text.length; i += 1) {
    const char = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === '\\') {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }
    if (char === '"') {
      inString = true;
      continue;
    }
    if (char === '{') {
      depth += 1;
    } else if (char === '}') {
      depth -= 1;
      if (depth === 0) return i + 1;
    }
  }
  return -1;
}

function extractRawJsonObjectValue(text, key) {
  const needle = JSON.stringify(key);
  let index = text.indexOf(needle);
  while (index >= 0) {
    let cursor = index + needle.length;
    while (/\s/.test(text[cursor] || '')) cursor += 1;
    if (text[cursor] !== ':') {
      index = text.indexOf(needle, index + 1);
      continue;
    }
    cursor += 1;
    while (/\s/.test(text[cursor] || '')) cursor += 1;
    if (text[cursor] !== '{') {
      index = text.indexOf(needle, index + 1);
      continue;
    }
    const end = findRawJsonObjectEnd(text, cursor);
    if (end > cursor) return text.slice(cursor, end);
    return '';
  }
  return '';
}

function verifyAlipayContentSignature(content, sign, publicKey) {
  if (!String(content || '').trim() || !String(sign || '').trim()) return false;
  try {
    return crypto
      .createVerify('RSA-SHA256')
      .update(content, 'utf8')
      .end()
      .verify(publicKeyObject(publicKey), sign, 'base64');
  } catch {
    return false;
  }
}

export function verifyAlipayApiResponseSignature(response, publicKey) {
  const rawText = typeof response === 'string' ? response : '';
  const json = parseJsonResponse(response);
  const responseKey = Object.keys(json).find(
    (key) => key !== 'sign' && key !== 'sign_type' && key.endsWith('_response'),
  );
  if (!responseKey) return false;
  const content = rawText
    ? extractRawJsonObjectValue(rawText, responseKey)
    : JSON.stringify(json[responseKey]);
  return verifyAlipayContentSignature(content, json.sign, publicKey);
}

export async function queryAlipayTradeByOutTradeNo({
  appId,
  privateKey,
  publicKey,
  gatewayUrl,
  outTradeNo,
  fetchImpl = fetch,
}) {
  const body = buildAlipayTradeQueryBody({
    appId,
    privateKey,
    outTradeNo,
  });
  const response = await fetchImpl(gatewayUrl, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
    },
    body,
  });
  const text = await response.text();
  if (!response.ok) {
    throw Object.assign(new Error(`Alipay query failed: ${response.status}`), {
      statusCode: 502,
      upstreamBody: text.slice(0, 200),
    });
  }
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw Object.assign(new Error('Alipay query returned invalid JSON'), {
      statusCode: 502,
      upstreamBody: text.slice(0, 200),
    });
  }
  if (!verifyAlipayApiResponseSignature(text, publicKey)) {
    throw Object.assign(new Error('Alipay query signature verification failed'), {
      statusCode: 502,
    });
  }
  return json.alipay_trade_query_response || {};
}

export function isAlipayTradePaid(trade) {
  return ['TRADE_SUCCESS', 'TRADE_FINISHED'].includes(
    String(trade?.trade_status || '').trim().toUpperCase(),
  );
}
