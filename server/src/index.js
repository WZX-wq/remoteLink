import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import mysql from 'mysql2/promise';
import {
  buildAlipayAppPayOrderInfo,
  isAlipayTradePaid,
  queryAlipayTradeByOutTradeNo,
  verifyAlipaySignature,
} from './alipay.js';
import {
  normalizeAccountDeletionMode,
  submitAccountDeletion,
} from './account-deletion.js';
import {
  fetchAndValidateAppleTransaction,
  parseAppleProductMap,
  resolveAppleTransactionId,
} from './apple-iap.js';
import { parseAppleNotification } from './apple-notifications.js';
import { claimAppleSubscriptionOwner } from './apple-entitlement.js';
import { createRequestGate } from './request-gate.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const defaultInstallerPath = path.resolve(
  __dirname,
  '../public/downloads/Kunqiong-Remote-Desktop-Setup.exe',
);
const defaultInstallerSha256 =
  '4C3E608C6AF09F6BEE70597DA0691253F0771C0E1E6F7CD8200F87A05826341A';
const defaultAndroidApkPath = path.resolve(
  __dirname,
  '../public/downloads/Kunqiong-Remote-Desktop.apk',
);
const defaultAndroidApkSha256 =
  '1158207394F9E5A875CDDDBB45A01BE7A3789557157888C6B3A9700095165C8B';
const defaultRequestGateStateFile = path.resolve(
  __dirname,
  '../data/request-gate.json',
);
const defaultAdminGateToken = 'qwertyuiopasdfghjklzxcvbnm';

const config = {
  host: process.env.KQ_API_HOST || '0.0.0.0',
  port: Number.parseInt(process.env.KQ_API_PORT || '21120', 10),
  publicApiUrl: process.env.KQ_PUBLIC_API_URL || '',
  db: {
    host: mustEnv('KQ_DB_HOST'),
    port: Number.parseInt(process.env.KQ_DB_PORT || '3306', 10),
    user: mustEnv('KQ_DB_USER'),
    password: mustEnv('KQ_DB_PASSWORD'),
    database: process.env.KQ_DB_NAME || 'kq_remote_link',
  },
  apiWebBaseUrl:
    (process.env.KQ_API_WEB_BASE_URL || 'https://api-web.kunqiongai.com')
      .replace(/\/+$/, ''),
  subsiteName: process.env.KQ_SUBSITE_NAME || 'https://remote.kunqiongai.com/',
  downloadUrl:
    process.env.KQ_DOWNLOAD_URL ||
    deriveDownloadUrl(process.env.KQ_PUBLIC_API_URL, 'windows') ||
    '/download/windows',
  androidDownloadUrl:
    process.env.KQ_ANDROID_DOWNLOAD_URL ||
    deriveDownloadUrl(process.env.KQ_PUBLIC_API_URL, 'android') ||
    '/download/android',
  download: {
    filePath: process.env.KQ_DOWNLOAD_FILE_PATH || defaultInstallerPath,
    fileName:
      process.env.KQ_DOWNLOAD_FILE_NAME ||
      'Kunqiong-Remote-Desktop-Setup.exe',
    version: process.env.KQ_DOWNLOAD_VERSION || '2026.06.26.2060',
    sha256: process.env.KQ_DOWNLOAD_SHA256 || defaultInstallerSha256,
    maxRequestsPerWindow: envInt('KQ_DOWNLOAD_MAX_REQUESTS_PER_WINDOW', 12, 1, 120),
    windowMs: envInt('KQ_DOWNLOAD_RATE_WINDOW_MS', 60000, 1000, 3600000),
    maxPerIpConcurrent: envInt('KQ_DOWNLOAD_MAX_PER_IP_CONCURRENT', 2, 1, 16),
    maxGlobalConcurrent: envInt('KQ_DOWNLOAD_MAX_GLOBAL_CONCURRENT', 8, 1, 128),
  },
  androidDownload: {
    filePath: process.env.KQ_ANDROID_DOWNLOAD_FILE_PATH || defaultAndroidApkPath,
    fileName:
      process.env.KQ_ANDROID_DOWNLOAD_FILE_NAME ||
      'Kunqiong-Remote-Desktop.apk',
    version:
      process.env.KQ_ANDROID_DOWNLOAD_VERSION ||
      process.env.KQ_DOWNLOAD_VERSION ||
      '1.4.6+4067',
    sha256: process.env.KQ_ANDROID_DOWNLOAD_SHA256 || defaultAndroidApkSha256,
  },
  wechatPay: {
    appId: process.env.KQ_WECHAT_PAY_APPID || '',
    mchId: process.env.KQ_WECHAT_PAY_MCHID || '',
    merchantSerialNo: process.env.KQ_WECHAT_PAY_MERCHANT_SERIAL_NO || '',
    privateKey:
      process.env.KQ_WECHAT_PAY_PRIVATE_KEY ||
      readOptionalSecretFile(process.env.KQ_WECHAT_PAY_PRIVATE_KEY_PATH),
    apiV3Key: process.env.KQ_WECHAT_PAY_API_V3_KEY || '',
    notifyUrl: process.env.KQ_WECHAT_PAY_NOTIFY_URL || '',
    apiBaseUrl:
      (process.env.KQ_WECHAT_PAY_API_BASE_URL || 'https://api.mch.weixin.qq.com')
        .replace(/\/+$/, ''),
  },
  alipayPay: {
    appId: process.env.KQ_ALIPAY_APP_ID || process.env.KQ_ALIPAY_APPID || '',
    privateKey:
      process.env.KQ_ALIPAY_PRIVATE_KEY ||
      readOptionalSecretFile(process.env.KQ_ALIPAY_PRIVATE_KEY_PATH),
    publicKey:
      process.env.KQ_ALIPAY_PUBLIC_KEY ||
      readOptionalSecretFile(process.env.KQ_ALIPAY_PUBLIC_KEY_PATH),
    notifyUrl: process.env.KQ_ALIPAY_NOTIFY_URL || '',
    gatewayUrl:
      (process.env.KQ_ALIPAY_GATEWAY_URL || 'https://openapi.alipay.com/gateway.do')
        .replace(/\/+$/, ''),
  },
  accountDeletion: {
    mode: normalizeAccountDeletionMode(process.env.KQ_ACCOUNT_DELETION_MODE),
    upstreamUrl: process.env.KQ_IDENTITY_ACCOUNT_DELETE_URL || '',
  },
  appleIap: {
    productsJson: process.env.KQ_IOS_IAP_PRODUCTS || '',
    bundleId: process.env.KQ_APPLE_IAP_BUNDLE_ID || '',
    issuerId: process.env.KQ_APPLE_IAP_ISSUER_ID || '',
    keyId: process.env.KQ_APPLE_IAP_KEY_ID || '',
    privateKey:
      process.env.KQ_APPLE_IAP_PRIVATE_KEY ||
      readOptionalSecretFile(process.env.KQ_APPLE_IAP_PRIVATE_KEY_PATH),
    environment: process.env.KQ_APPLE_IAP_ENVIRONMENT || 'sandbox',
  },
  appScheme: normalizeUriScheme(process.env.KQ_APP_SCHEME || 'kqremote'),
  requestGate: {
    stateFile:
      process.env.KQ_REQUEST_GATE_STATE_FILE || defaultRequestGateStateFile,
    adminToken: process.env.KQ_ADMIN_GATE_TOKEN || defaultAdminGateToken,
  },
};

const kqIconAssetPath = 'assets/kq-icon.png';

let pool;
const downloadLimiter = {
  active: 0,
  clients: new Map(),
};
const identityContextCache = new Map();
const identityContextInFlight = new Map();
const identityContextCacheTtlMs = 60 * 1000;

function mustEnv(name) {
  const value = process.env[name];
  if (!value || !value.trim()) {
    throw new Error(`${name} is required`);
  }
  return value.trim();
}

function readOptionalSecretFile(filePath) {
  const text = String(filePath || '').trim();
  if (!text) return '';
  try {
    return fs.readFileSync(text, 'utf8').trim();
  } catch (error) {
    console.error(`Failed to read secret file ${text}: ${error.message}`);
    return '';
  }
}

function deriveDownloadUrl(publicApiUrl, platform = 'windows') {
  const text = String(publicApiUrl || '').trim();
  if (!text) return '';
  try {
    const url = new URL(text);
    url.pathname = url.pathname.replace(/\/api\/?$/, '').replace(/\/+$/, '');
    url.pathname = `${url.pathname}/download/${platform}`;
    url.search = '';
    url.hash = '';
    return url.toString();
  } catch {
    return '';
  }
}

function envInt(name, fallback, min, max) {
  const parsed = Number.parseInt(process.env[name] || '', 10);
  const value = Number.isFinite(parsed) ? parsed : fallback;
  return Math.max(min, Math.min(max, value));
}

function assertIdentifier(value, name) {
  if (!/^[A-Za-z0-9_]+$/.test(value)) {
    throw new Error(`${name} must contain only letters, numbers, and underscores`);
  }
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function getAuthToken(req) {
  const headerToken = req.get('token') || req.get('x-kq-token') || '';
  const authorization = req.get('authorization') || '';
  const bearer = authorization.replace(/^Bearer\s+/i, '').trim();
  const bodyToken = req.body?.token || req.query?.token || '';
  return String(headerToken || bearer || bodyToken).trim();
}

function jsonError(res, status, message) {
  return res.status(status).json({ ok: false, error: message });
}

function collectStringValues(value, out = []) {
  if (typeof value === 'string') {
    const text = value.trim();
    if (text) {
      out.push(text);
      const matches = text.match(/[a-z][a-z0-9+.-]*:\/\/[^\s"'<>]+/gi);
      if (matches) {
        out.push(...matches.map((item) => item.trim()).filter(Boolean));
      }
    }
    return out;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      collectStringValues(item, out);
    }
    return out;
  }
  if (value && typeof value === 'object') {
    for (const item of Object.values(value)) {
      collectStringValues(item, out);
    }
  }
  return out;
}

function firstPaymentUrl(values, matchers) {
  for (const value of values) {
    const text = String(value || '').trim();
    if (!text) continue;
    const lower = text.toLowerCase();
    if (matchers.some((matcher) => matcher(lower, text))) {
      return text;
    }
  }
  return '';
}

function collectObjectValues(value, out = []) {
  if (typeof value === 'string') {
    const text = value.trim();
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        collectObjectValues(JSON.parse(text), out);
      } catch (_) {
        // Plain text fields are expected in payment payloads.
      }
    }
    return out;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      collectObjectValues(item, out);
    }
    return out;
  }
  if (value && typeof value === 'object') {
    out.push(value);
    const preferredKeys = [
      'wechat_app_pay',
      'wechatAppPay',
      'wechat_pay',
      'wechatPay',
      'wx_pay',
      'wxPay',
      'app_pay',
      'appPay',
      'pay_params',
      'payParams',
      'payment_params',
      'paymentParams',
      'payment',
    ];
    for (const key of preferredKeys) {
      if (Object.prototype.hasOwnProperty.call(value, key)) {
        collectObjectValues(value[key], out);
      }
    }
    for (const item of Object.values(value)) {
      collectObjectValues(item, out);
    }
  }
  return out;
}

function firstObjectString(source, keys) {
  for (const key of keys) {
    const text = String(source?.[key] ?? '').trim();
    if (text) return text;
  }
  return '';
}

function normalizeWechatAppPayRequest(value) {
  for (const source of collectObjectValues(value)) {
    const appId = firstObjectString(source, ['appId', 'appid', 'app_id']);
    const partnerId = firstObjectString(source, [
      'partnerId',
      'partnerid',
      'partner_id',
      'mchId',
      'mchid',
      'mch_id',
    ]);
    const prepayId = firstObjectString(source, ['prepayId', 'prepayid', 'prepay_id']);
    const packageValue = firstObjectString(source, [
      'packageValue',
      'package_value',
      'package',
      'packageStr',
    ]) || (appId && partnerId && prepayId ? 'Sign=WXPay' : '');
    const nonceStr = firstObjectString(source, [
      'nonceStr',
      'noncestr',
      'nonce_str',
      'nonce',
    ]);
    const timeStamp = firstObjectString(source, ['timeStamp', 'timestamp', 'time_stamp']);
    const sign = firstObjectString(source, ['sign', 'paySign', 'paysign']);
    if (!appId || !partnerId || !prepayId || !packageValue || !nonceStr || !timeStamp || !sign) {
      continue;
    }
    return { appId, partnerId, prepayId, packageValue, nonceStr, timeStamp, sign };
  }
  return null;
}

function normalizeMemberOrderPaymentLinks(order) {
  const values = collectStringValues(order);
  const wechatMatchers = [
    (lower) => lower.startsWith('weixin://'),
  ];
  const alipayMatchers = [
    (lower) => lower.startsWith('alipays://'),
    (lower) => lower.startsWith('alipayqr://'),
  ];
  const wechatAppUrl =
    firstPaymentUrl([order?.wechat_app_url, order?.wechatAppUrl], wechatMatchers) ||
    firstPaymentUrl(values, wechatMatchers);
  const alipayAppUrl =
    firstPaymentUrl([order?.alipay_app_url, order?.alipayAppUrl], alipayMatchers) ||
    firstPaymentUrl(values, alipayMatchers);
  const payType = Number(order?.pay_type || 0);
  const paymentAppUrl =
    firstPaymentUrl(
      [order?.payment_app_url, order?.paymentAppUrl],
      payType === 2 ? alipayMatchers : wechatMatchers,
    ) || (payType === 2 ? alipayAppUrl : wechatAppUrl);
  const normalized = {
    ...order,
    wechat_app_url: wechatAppUrl,
    alipay_app_url: alipayAppUrl,
    payment_app_url: paymentAppUrl,
  };
  const wechatAppPay = normalizeWechatAppPayRequest(order);
  if (wechatAppPay) {
    normalized.wechat_app_pay = wechatAppPay;
  }
  return normalized;
}

function getWechatPayConfig() {
  const cfg = config.wechatPay;
  if (
    !cfg.appId.trim() ||
    !cfg.mchId.trim() ||
    !cfg.merchantSerialNo.trim() ||
    !cfg.privateKey.trim()
  ) {
    return null;
  }
  return {
    appId: cfg.appId.trim(),
    mchId: cfg.mchId.trim(),
    merchantSerialNo: cfg.merchantSerialNo.trim(),
    privateKey: cfg.privateKey.trim().replace(/\\n/g, '\n'),
    apiV3Key: cfg.apiV3Key.trim(),
    notifyUrl: cfg.notifyUrl.trim(),
    apiBaseUrl: cfg.apiBaseUrl,
  };
}

function getAlipayPayConfig() {
  const cfg = config.alipayPay;
  if (!cfg.appId.trim() || !cfg.privateKey.trim() || !cfg.publicKey.trim()) {
    return null;
  }
  return {
    appId: cfg.appId.trim(),
    privateKey: cfg.privateKey.trim(),
    publicKey: cfg.publicKey.trim(),
    notifyUrl: cfg.notifyUrl.trim(),
    gatewayUrl: cfg.gatewayUrl,
  };
}

function wechatNonce(size = 16) {
  return crypto.randomBytes(size).toString('hex').slice(0, 32);
}

function signWechatRsaSha256(message, privateKey) {
  return crypto
    .createSign('RSA-SHA256')
    .update(message)
    .end()
    .sign(privateKey, 'base64');
}

function buildWechatAuthorization(method, pathWithQuery, body, cfg) {
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const nonce = wechatNonce();
  const message = `${method}\n${pathWithQuery}\n${timestamp}\n${nonce}\n${body}\n`;
  const signature = signWechatRsaSha256(message, cfg.privateKey);
  return `WECHATPAY2-SHA256-RSA2048 mchid="${cfg.mchId}",nonce_str="${nonce}",timestamp="${timestamp}",serial_no="${cfg.merchantSerialNo}",signature="${signature}"`;
}

async function requestWechatPay(method, pathWithQuery, payload, cfg) {
  const body = payload == null ? '' : JSON.stringify(payload);
  const response = await fetch(`${cfg.apiBaseUrl}${pathWithQuery}`, {
    method,
    headers: {
      Accept: 'application/json',
      Authorization: buildWechatAuthorization(method, pathWithQuery, body, cfg),
      'Content-Type': 'application/json',
    },
    body: method === 'GET' ? undefined : body,
  });
  const text = await response.text();
  let json = {};
  if (text.trim()) {
    try {
      json = JSON.parse(text);
    } catch {
      throw Object.assign(new Error('WeChat Pay returned invalid JSON'), {
        statusCode: 502,
        upstreamBody: text.slice(0, 200),
      });
    }
  }
  if (!response.ok) {
    throw Object.assign(
      new Error(json.message || json.code || `WeChat Pay failed: ${response.status}`),
      { statusCode: 502, upstream: json },
    );
  }
  return json;
}

function buildWechatAppPayRequest(prepayId, cfg) {
  const timeStamp = Math.floor(Date.now() / 1000).toString();
  const nonceStr = wechatNonce();
  const message = `${cfg.appId}\n${timeStamp}\n${nonceStr}\n${prepayId}\n`;
  return {
    appId: cfg.appId,
    partnerId: cfg.mchId,
    prepayId,
    packageValue: 'Sign=WXPay',
    nonceStr,
    timeStamp,
    sign: signWechatRsaSha256(message, cfg.privateKey),
  };
}

function makeProjectMemberOrderNo(userId, packageId) {
  const suffix = crypto.randomBytes(4).toString('hex');
  return `KQ${Date.now().toString(36).toUpperCase()}${Number(userId || 0).toString(36).toUpperCase()}${Number(packageId || 0).toString(36).toUpperCase()}${suffix}`.slice(0, 32);
}

function findMemberPackage(memberInfo, packageId) {
  const packages = Array.isArray(memberInfo?.packages) ? memberInfo.packages : [];
  return packages.find((item) => Number(item?.id || 0) === Number(packageId));
}

function centsFromYuan(value) {
  const amount = Number(value || 0);
  if (!Number.isFinite(amount) || amount <= 0) return 0;
  return Math.round(amount * 100);
}

function isoExpireAfterMinutes(minutes) {
  return new Date(Date.now() + minutes * 60 * 1000).toISOString().replace('.000Z', '+00:00');
}

function addDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function formatMysqlDateTime(date) {
  const pad = (value) => String(value).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

function localMemberExpireAtFromOrder(row) {
  const days = Number(row?.package_days || 0);
  if (days >= 999999) return '9999-12-31 23:59:59';
  const base = row?.expire_at ? new Date(row.expire_at) : new Date();
  if (Number.isNaN(base.getTime())) return formatMysqlDateTime(addDays(new Date(), Math.max(1, days)));
  return formatMysqlDateTime(addDays(base, Math.max(1, days)));
}

function overlayProjectMemberInfo(memberInfo, activeOrder) {
  if (!activeOrder) return memberInfo;
  return {
    ...(memberInfo || {}),
    web_member_active: true,
    web_member_expire_at: activeOrder.expire_at,
    subsite_name: memberInfo?.subsite_name || config.subsiteName,
  };
}

async function latestPaidProjectMemberOrder(userId, executor = pool) {
  const [rows] = await executor.execute(
    `
      SELECT *
      FROM kq_member_orders
      WHERE user_id = ? AND pay_status = 1
        AND (expire_at IS NULL OR expire_at > NOW())
      ORDER BY expire_at DESC, updated_at DESC
      LIMIT 1
    `,
    [userId],
  );
  return rows[0] || null;
}

async function markProjectMemberOrderPaid(orderNo, wechatOrder = {}) {
  const [rows] = await pool.execute(
    'SELECT * FROM kq_member_orders WHERE order_no = ? LIMIT 1',
    [orderNo],
  );
  const row = rows[0];
  if (!row) return null;
  const expireAt = row.expire_at || localMemberExpireAtFromOrder(row);
  let previousRaw = {};
  try {
    previousRaw =
      typeof row.raw_order_json === 'string'
        ? JSON.parse(row.raw_order_json || '{}')
        : row.raw_order_json || {};
  } catch (_) {
    previousRaw = {};
  }
  const raw = {
    ...previousRaw,
    wechat_order: wechatOrder,
  };
  await pool.execute(
    `
      UPDATE kq_member_orders
      SET pay_status = 1, expire_at = ?, raw_order_json = ?, updated_at = NOW()
      WHERE order_no = ?
    `,
    [expireAt, JSON.stringify(raw), orderNo],
  );
  await pool.execute(
    `
      UPDATE kq_users
      SET member_active = 1, member_expire_at = ?, last_seen_at = NOW()
      WHERE id = ?
    `,
    [expireAt, row.user_id],
  );
  return {
    ...row,
    pay_status: 1,
    expire_at: expireAt,
  };
}

function getAppleIapConfig() {
  return {
    ...config.appleIap,
    productMap: parseAppleProductMap(config.appleIap.productsJson),
  };
}

function appleMembershipOrderNo(originalTransactionId) {
  return `APPLE-${String(originalTransactionId || '').trim()}`.slice(0, 64);
}

function appleMembershipExpiry(memberPackage, transaction) {
  if (transaction.expiresAt) return transaction.expiresAt;
  const packageDays = Number(memberPackage?.days || 0);
  if (packageDays >= 999999) return '9999-12-31 23:59:59';
  return formatMysqlDateTime(addDays(new Date(), Math.max(1, packageDays)));
}

function isMembershipExpiryActive(expireAt) {
  if (!expireAt || expireAt === '9999-12-31 23:59:59') return true;
  const timestamp = expireAt instanceof Date
    ? expireAt.getTime()
    : new Date(String(expireAt).replace(' ', 'T') + 'Z').getTime();
  return Number.isFinite(timestamp) && timestamp > Date.now();
}

async function grantAppleMembership({ ctx, packageId, memberPackage, transaction }) {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const [existingTransactions] = await connection.execute(
      'SELECT * FROM kq_apple_transactions WHERE transaction_id = ? FOR UPDATE',
      [transaction.transactionId],
    );
    const existingTransaction = existingTransactions[0];
    if (existingTransaction && Number(existingTransaction.user_id) !== Number(ctx.user.id)) {
      throw Object.assign(
        new Error('This Apple purchase has already been used by another account.'),
        { statusCode: 409 },
      );
    }
    await claimAppleSubscriptionOwner(connection, {
      originalTransactionId: transaction.originalTransactionId,
      userId: ctx.user.id,
    });

    const orderNo = appleMembershipOrderNo(transaction.originalTransactionId);
    const expireAt = appleMembershipExpiry(memberPackage, transaction);
    const memberActive = isMembershipExpiryActive(expireAt);
    const packageName = String(memberPackage?.name || 'Kunqiong membership').slice(0, 128);
    const packageDays = Number(memberPackage?.days || 0);
    const payAmount = Number(memberPackage?.price_yuan || 0);
    const rawTransaction = {
      payment_provider: 'apple_iap',
      transaction_id: transaction.transactionId,
      original_transaction_id: transaction.originalTransactionId,
      product_id: transaction.productId,
      environment: transaction.environment,
      signed_transaction_info: transaction.signedTransactionInfo,
      claims: transaction.claims,
    };

    await connection.execute(
      `
        INSERT INTO kq_member_orders (
          user_id, order_no, package_id, package_name, package_days,
          pay_amount, pay_type, pay_status, expire_at, raw_order_json
        )
        VALUES (?, ?, ?, ?, ?, ?, 3, 1, ?, ?)
        ON DUPLICATE KEY UPDATE
          package_id = VALUES(package_id),
          package_name = VALUES(package_name),
          package_days = VALUES(package_days),
          pay_amount = VALUES(pay_amount),
          pay_type = 3,
          pay_status = 1,
          expire_at = VALUES(expire_at),
          raw_order_json = VALUES(raw_order_json),
          updated_at = NOW()
      `,
      [
        ctx.user.id,
        orderNo,
        Number(packageId),
        packageName,
        packageDays,
        Number.isFinite(payAmount) ? payAmount : 0,
        expireAt,
        JSON.stringify(rawTransaction),
      ],
    );
    await connection.execute(
      `
        INSERT INTO kq_apple_transactions (
          transaction_id, original_transaction_id, user_id, package_id, product_id,
          environment, expires_at, purchase_at, signed_transaction_hash, raw_transaction_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
          original_transaction_id = VALUES(original_transaction_id),
          package_id = VALUES(package_id),
          product_id = VALUES(product_id),
          environment = VALUES(environment),
          expires_at = VALUES(expires_at),
          purchase_at = VALUES(purchase_at),
          signed_transaction_hash = VALUES(signed_transaction_hash),
          raw_transaction_json = VALUES(raw_transaction_json),
          verified_at = NOW()
      `,
      [
        transaction.transactionId,
        transaction.originalTransactionId,
        ctx.user.id,
        Number(packageId),
        transaction.productId,
        transaction.environment,
        transaction.expiresAt,
        transaction.purchaseDate,
        sha256(transaction.signedTransactionInfo),
        JSON.stringify(rawTransaction),
      ],
    );
    await connection.execute(
      `
        UPDATE kq_users
        SET member_active = ?, member_expire_at = ?, last_seen_at = NOW()
        WHERE id = ?
      `,
      [memberActive ? 1 : 0, expireAt, ctx.user.id],
    );
    await connection.commit();
    return { expireAt, memberActive };
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}

function parseStoredMemberInfo(value) {
  if (value && typeof value === 'object' && !Array.isArray(value)) return value;
  try {
    const parsed = JSON.parse(String(value || '{}'));
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
      ? parsed
      : {};
  } catch (_) {
    return {};
  }
}

function appleConfigForNotification(appleConfig, environment) {
  if (environment !== 'sandbox' && environment !== 'production') {
    return appleConfig;
  }
  return { ...appleConfig, environment };
}

async function findAppleNotificationMembershipContext(
  originalTransactionId,
  packageId,
) {
  const orderNo = appleMembershipOrderNo(originalTransactionId);
  const [rows] = await pool.execute(
    `
      SELECT
        owner.user_id,
        member_order.package_id,
        member_order.package_name,
        member_order.package_days,
        member_order.pay_amount,
        snapshot.raw_member_json
      FROM kq_apple_subscription_owners AS owner
      LEFT JOIN kq_member_orders AS member_order
        ON member_order.user_id = owner.user_id
        AND member_order.order_no = ?
      LEFT JOIN kq_member_snapshots AS snapshot
        ON snapshot.id = (
          SELECT latest_snapshot.id
          FROM kq_member_snapshots AS latest_snapshot
          WHERE latest_snapshot.user_id = owner.user_id
          ORDER BY latest_snapshot.synced_at DESC, latest_snapshot.id DESC
          LIMIT 1
        )
      WHERE owner.original_transaction_id = ?
      LIMIT 1
    `,
    [orderNo, originalTransactionId],
  );
  const row = rows[0];
  if (!row) return null;

  const memberInfo = parseStoredMemberInfo(row.raw_member_json);
  let memberPackage = findMemberPackage(memberInfo, packageId);
  if (!memberPackage && Number(row.package_id) === Number(packageId)) {
    memberPackage = {
      id: Number(row.package_id),
      name: row.package_name,
      days: Number(row.package_days || 0),
      price_yuan: Number(row.pay_amount || 0),
    };
  }
  if (!memberPackage) return null;

  return {
    ctx: { user: { id: row.user_id } },
    memberPackage,
  };
}

async function revokeAppleMembership({ userId, originalTransactionId, transaction }) {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    await connection.execute(
      `
        UPDATE kq_member_orders
        SET pay_status = 0, updated_at = NOW()
        WHERE user_id = ? AND order_no = ? AND pay_type = 3
      `,
      [userId, appleMembershipOrderNo(originalTransactionId)],
    );
    await connection.execute(
      `
        UPDATE kq_apple_transactions
        SET expires_at = ?, updated_at = NOW()
        WHERE original_transaction_id = ?
      `,
      [
        transaction.revocationDate || transaction.expiresAt || formatMysqlDateTime(new Date()),
        originalTransactionId,
      ],
    );
    const activeOrder = await latestPaidProjectMemberOrder(userId, connection);
    const expireAt = activeOrder?.expire_at || null;
    await connection.execute(
      `
        UPDATE kq_users
        SET member_active = ?, member_expire_at = ?, last_seen_at = NOW()
        WHERE id = ?
      `,
      [activeOrder ? 1 : 0, expireAt, userId],
    );
    await connection.commit();
    return { expireAt, memberActive: Boolean(activeOrder) };
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}

async function queryWechatAppOrderStatus(orderNo, cfg) {
  const pathWithQuery =
    `/v3/pay/transactions/out-trade-no/${encodeURIComponent(orderNo)}?mchid=${encodeURIComponent(cfg.mchId)}`;
  return await requestWechatPay('GET', pathWithQuery, null, cfg);
}

async function createWechatAppMemberOrder({ ctx, packageId, req }) {
  const cfg = getWechatPayConfig();
  if (!cfg) return null;
  const memberPackage = findMemberPackage(ctx.memberInfo, packageId);
  if (!memberPackage) {
    throw Object.assign(new Error('Membership package not found'), { statusCode: 404 });
  }
  const total = centsFromYuan(memberPackage.price_yuan);
  if (total <= 0) {
    throw Object.assign(new Error('Membership package price is invalid'), { statusCode: 400 });
  }
  const orderNo = makeProjectMemberOrderNo(ctx.user.id, packageId);
  const notifyUrl =
    cfg.notifyUrl ||
    (config.publicApiUrl
      ? `${config.publicApiUrl.replace(/\/+$/, '')}/wechat-pay/notify`
      : '');
  if (!notifyUrl) {
    throw Object.assign(new Error('KQ_WECHAT_PAY_NOTIFY_URL or KQ_PUBLIC_API_URL is required for WeChat APP Pay'), {
      statusCode: 500,
    });
  }
  const packageName = String(memberPackage.name || 'Kunqiong membership').slice(0, 80);
  const packageDays = Number(memberPackage.days || 0);
  const payload = {
    appid: cfg.appId,
    mchid: cfg.mchId,
    description: packageName || 'Kunqiong membership',
    out_trade_no: orderNo,
    time_expire: isoExpireAfterMinutes(30),
    attach: JSON.stringify({ user_id: ctx.user.id, package_id: packageId }).slice(0, 128),
    notify_url: notifyUrl,
    amount: {
      total,
      currency: 'CNY',
    },
    scene_info: {
      payer_client_ip: getClientIp(req),
    },
  };
  const result = await requestWechatPay('POST', '/v3/pay/transactions/app', payload, cfg);
  const prepayId = String(result.prepay_id || '').trim();
  if (!prepayId) {
    throw Object.assign(new Error('WeChat Pay did not return prepay_id'), {
      statusCode: 502,
      upstream: result,
    });
  }
  const order = normalizeMemberOrderPaymentLinks({
    order_no: orderNo,
    package_id: packageId,
    package_name: packageName,
    package_days: packageDays,
    pay_amount: total / 100,
    pay_type: 1,
    subsite_name: config.subsiteName,
    qrcode_img_url: '',
    code_url: '',
    wechat_app_pay: buildWechatAppPayRequest(prepayId, cfg),
    payment_provider: 'wechat_app',
    prepay_id: prepayId,
  });
  await pool.execute(
    `
      INSERT INTO kq_member_orders (
        user_id, order_no, package_id, package_name, package_days,
        pay_amount, pay_type, raw_order_json
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `,
    [
      ctx.user.id,
      order.order_no,
      Number(order.package_id || 0),
      String(order.package_name || ''),
      Number(order.package_days || 0),
      Number(order.pay_amount || 0),
      Number(order.pay_type || 0),
      JSON.stringify(order),
    ],
  );
  return order;
}

function localMemberOrderRawJson(row) {
  if (!row) return {};
  try {
    return typeof row.raw_order_json === 'string'
      ? JSON.parse(row.raw_order_json || '{}')
      : row.raw_order_json || {};
  } catch {
    return {};
  }
}

function isProjectAlipayAppOrder(row) {
  const raw = localMemberOrderRawJson(row);
  return Number(row?.pay_type || 0) === 2 && raw?.payment_provider === 'alipay_app';
}

function alipayNotifyUrl(cfg) {
  return cfg.notifyUrl ||
    (config.publicApiUrl
      ? `${config.publicApiUrl.replace(/\/+$/, '')}/alipay/notify`
      : '');
}

function assertAlipayOrderMatches(row, trade, cfg) {
  if (trade?.app_id && String(trade.app_id) !== cfg.appId) {
    throw Object.assign(new Error('Alipay app_id does not match this application'), {
      statusCode: 400,
    });
  }
  const totalAmount = String(trade?.total_amount || '').trim();
  if (!totalAmount) return;
  const expected = Number(row?.pay_amount || 0).toFixed(2);
  const actual = Number(totalAmount || 0).toFixed(2);
  if (expected !== actual) {
    throw Object.assign(new Error('Alipay total_amount does not match local order'), {
      statusCode: 400,
    });
  }
}

async function createAlipayAppMemberOrder({ ctx, packageId }) {
  const cfg = getAlipayPayConfig();
  if (!cfg) return null;
  const memberPackage = findMemberPackage(ctx.memberInfo, packageId);
  if (!memberPackage) {
    throw Object.assign(new Error('Membership package not found'), { statusCode: 404 });
  }
  const total = centsFromYuan(memberPackage.price_yuan);
  if (total <= 0) {
    throw Object.assign(new Error('Membership package price is invalid'), { statusCode: 400 });
  }
  const notifyUrl = alipayNotifyUrl(cfg);
  if (!notifyUrl) {
    throw Object.assign(new Error('KQ_ALIPAY_NOTIFY_URL or KQ_PUBLIC_API_URL is required for Alipay APP Pay'), {
      statusCode: 500,
    });
  }
  const orderNo = makeProjectMemberOrderNo(ctx.user.id, packageId);
  const packageName = String(memberPackage.name || 'Kunqiong membership').slice(0, 80);
  const packageDays = Number(memberPackage.days || 0);
  const appOrderInfo = buildAlipayAppPayOrderInfo({
    appId: cfg.appId,
    privateKey: cfg.privateKey,
    notifyUrl,
    outTradeNo: orderNo,
    totalAmount: total / 100,
    subject: packageName || 'Kunqiong membership',
  });
  const order = {
    ...normalizeMemberOrderPaymentLinks({
      order_no: orderNo,
      package_id: packageId,
      package_name: packageName,
      package_days: packageDays,
      pay_amount: total / 100,
      pay_type: 2,
      subsite_name: config.subsiteName,
      qrcode_img_url: '',
      code_url: '',
    }),
    alipay_app_url: appOrderInfo,
    payment_app_url: appOrderInfo,
    payment_provider: 'alipay_app',
  };
  await pool.execute(
    `
      INSERT INTO kq_member_orders (
        user_id, order_no, package_id, package_name, package_days,
        pay_amount, pay_type, raw_order_json
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `,
    [
      ctx.user.id,
      order.order_no,
      Number(order.package_id || 0),
      String(order.package_name || ''),
      Number(order.package_days || 0),
      Number(order.pay_amount || 0),
      Number(order.pay_type || 0),
      JSON.stringify(order),
    ],
  );
  return order;
}

async function queryAlipayAppOrderStatus(orderNo, cfg) {
  return queryAlipayTradeByOutTradeNo({
    appId: cfg.appId,
    privateKey: cfg.privateKey,
    publicKey: cfg.publicKey,
    gatewayUrl: cfg.gatewayUrl,
    outTradeNo: orderNo,
  });
}

async function handleAlipayPayNotification(body) {
  const cfg = getAlipayPayConfig();
  if (!cfg) return false;
  if (!verifyAlipaySignature(body, cfg.publicKey, { includeSignType: false })) {
    throw Object.assign(new Error('Alipay notification signature verification failed'), {
      statusCode: 400,
    });
  }
  if (String(body?.app_id || '') !== cfg.appId) {
    throw Object.assign(new Error('Alipay notification app_id does not match this application'), {
      statusCode: 400,
    });
  }
  const orderNo = String(body?.out_trade_no || '').trim();
  if (!orderNo) return true;
  const [rows] = await pool.execute(
    'SELECT * FROM kq_member_orders WHERE order_no = ? LIMIT 1',
    [orderNo],
  );
  const localOrder = rows[0];
  if (!localOrder || !isProjectAlipayAppOrder(localOrder)) return true;
  assertAlipayOrderMatches(localOrder, body, cfg);
  if (isAlipayTradePaid(body)) {
    await markProjectMemberOrderPaid(orderNo, body);
  }
  return true;
}

function decryptWechatPayResource(resource, apiV3Key) {
  if (!apiV3Key || !resource || resource.algorithm !== 'AEAD_AES_256_GCM') {
    return null;
  }
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    Buffer.from(apiV3Key, 'utf8'),
    Buffer.from(String(resource.nonce || ''), 'utf8'),
  );
  const associatedData = String(resource.associated_data || '');
  if (associatedData) {
    decipher.setAAD(Buffer.from(associatedData, 'utf8'));
  }
  const ciphertext = Buffer.from(String(resource.ciphertext || ''), 'base64');
  const authTag = ciphertext.subarray(ciphertext.length - 16);
  const data = ciphertext.subarray(0, ciphertext.length - 16);
  decipher.setAuthTag(authTag);
  const plaintext = Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
  return JSON.parse(plaintext);
}

async function handleWechatPayNotification(body) {
  const cfg = getWechatPayConfig();
  if (!cfg?.apiV3Key) return false;
  if (body?.event_type !== 'TRANSACTION.SUCCESS') return true;
  const transaction = decryptWechatPayResource(body.resource, cfg.apiV3Key);
  const orderNo = String(transaction?.out_trade_no || '').trim();
  if (!orderNo || transaction?.trade_state !== 'SUCCESS') return true;
  await markProjectMemberOrderPaid(orderNo, transaction);
  return true;
}

function textError(res, status, message) {
  return res
    .status(status)
    .type('text')
    .send(message);
}

function toBool(value) {
  if (value === true || value === 1) return true;
  const text = String(value ?? '').trim().toLowerCase();
  return ['1', 'true', 'yes', 'y', 'on'].includes(text);
}

function envIsDisabled(value) {
  return ['0', 'false', 'no', 'n', 'off'].includes(
    String(value ?? '').trim().toLowerCase(),
  );
}

function normalizeUserPayload(data, token) {
  const source =
    data?.user && typeof data.user === 'object'
      ? data.user
      : data?.user_info && typeof data.user_info === 'object'
        ? data.user_info
        : data;
  const nickname = String(
    source?.nickname ?? source?.display_name ?? source?.displayName ?? source?.name ?? '',
  ).trim();
  const stableId = String(
    source?.id ?? source?.user_id ?? source?.uid ?? source?.uuid ?? source?.account_id ?? '',
  ).trim();
  const fallbackName = String(source?.username ?? source?.name ?? nickname).trim();
  const externalUserId = stableId || (nickname ? `nickname:${nickname}` : sha256(token).slice(0, 32));
  const username = fallbackName || externalUserId;
  return {
    externalUserId,
    username,
    nickname: nickname || fallbackName || username,
    email: String(source?.email ?? ''),
    avatarUrl: String(source?.avatar ?? source?.avatar_url ?? ''),
    raw: data ?? {},
    mergeNickname: nickname,
  };
}

async function postApiWeb(path, token, params = {}) {
  const body = new URLSearchParams({ ...params, token });
  const response = await fetch(`${config.apiWebBaseUrl}/user/${path}`, {
    method: 'POST',
    headers: {
      accept: 'application/json',
      'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
      token,
      authorization: `Bearer ${token}`,
    },
    body,
  });
  const text = await response.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw Object.assign(new Error('api-web returned invalid JSON'), {
      statusCode: 502,
      upstreamBody: text.slice(0, 200),
    });
  }
  if (response.status === 401 || Number(json.code) === 401) {
    throw Object.assign(new Error(json.msg || json.message || 'unauthorized'), {
      statusCode: 401,
    });
  }
  if (!response.ok || Number(json.code) !== 1) {
    throw Object.assign(
      new Error(json.msg || json.message || `api-web failed: ${response.status}`),
      { statusCode: 502, upstream: json },
    );
  }
  return json.data ?? {};
}

function getCachedIdentityContext(tokenHash) {
  const cached = identityContextCache.get(tokenHash);
  if (!cached) return null;
  if (Date.now() - cached.cachedAt > identityContextCacheTtlMs) {
    identityContextCache.delete(tokenHash);
    return null;
  }
  return cached.ctx;
}

function cacheIdentityContext(tokenHash, ctx) {
  identityContextCache.set(tokenHash, {
    cachedAt: Date.now(),
    ctx,
  });
}

function clearCachedIdentityContext(tokenHash) {
  identityContextCache.delete(tokenHash);
  identityContextInFlight.delete(tokenHash);
}

async function assertAccountDeletionDoesNotBlock(user) {
  if (config.accountDeletion.mode === 'local_test') return;
  const [rows] = await pool.execute(
    `
      SELECT status
      FROM kq_account_deletion_requests
      WHERE external_provider = ?
        AND external_user_id = ?
        AND status IN ('pending', 'processing', 'deleted')
      LIMIT 1
    `,
    [user.external_provider, user.external_user_id],
  );
  if (rows.length) {
    throw Object.assign(
      new Error('This account has a pending deletion request.'),
      { statusCode: 410 },
    );
  }
}

async function loadUserIdentityContextForToken(
  token,
  tokenHash,
  { allowPendingDeletion = false } = {},
) {
  const cached = getCachedIdentityContext(tokenHash);
  if (cached) {
    if (!allowPendingDeletion) {
      await assertAccountDeletionDoesNotBlock(cached.user);
    }
    return cached;
  }

  const inFlight = identityContextInFlight.get(tokenHash);
  if (inFlight) return await inFlight;

  const refreshPromise = (async () => {
    const userInfo = await postApiWeb('user_all_info', token);
    const user = normalizeUserPayload(userInfo, token);
    const dbUser = await upsertUserIdentity({
      ...user,
      tokenHash,
    });
    await mergeLegacyAccountRowsForUser(dbUser, user);
    if (!allowPendingDeletion) {
      await assertAccountDeletionDoesNotBlock(dbUser);
    }
    const ctx = { token, user: dbUser, userInfo };
    cacheIdentityContext(tokenHash, ctx);
    return ctx;
  })();

  identityContextInFlight.set(tokenHash, refreshPromise);
  try {
    return await refreshPromise;
  } finally {
    identityContextInFlight.delete(tokenHash);
  }
}

async function loadUserContext(req) {
  const token = getAuthToken(req);
  if (!token) {
    throw Object.assign(new Error('missing token'), { statusCode: 401 });
  }
  const tokenHash = sha256(token);
  const identity = await loadUserIdentityContextForToken(token, tokenHash);
  const memberInfo = await postApiWeb('get_web_member_package_info', token, {
    subsite_name: config.subsiteName,
  });
  const user = normalizeUserPayload(identity.userInfo, token);
  let dbUser = await upsertUser({
    ...user,
    tokenHash,
    memberActive: toBool(memberInfo.web_member_active),
    memberExpireAt: memberInfo.web_member_expire_at || null,
  });
  const paidOrder = await latestPaidProjectMemberOrder(dbUser.id);
  const mergedMemberInfo = overlayProjectMemberInfo(memberInfo, paidOrder);
  if (paidOrder) {
    await pool.execute(
      `
        UPDATE kq_users
        SET member_active = 1, member_expire_at = ?, last_seen_at = NOW()
        WHERE id = ?
      `,
      [paidOrder.expire_at, dbUser.id],
    );
    dbUser = {
      ...dbUser,
      member_active: 1,
      member_expire_at: paidOrder.expire_at,
    };
  }
  await mergeLegacyAccountRowsForUser(dbUser, user);
  await saveMemberSnapshot(dbUser, mergedMemberInfo);
  cacheIdentityContext(tokenHash, { token, user: dbUser, userInfo: identity.userInfo });
  return { token, user: dbUser, userInfo: identity.userInfo, memberInfo: mergedMemberInfo };
}

async function loadUserIdentityContext(req, options = {}) {
  const token = getAuthToken(req);
  if (!token) {
    throw Object.assign(new Error('missing token'), { statusCode: 401 });
  }
  const tokenHash = sha256(token);
  return await loadUserIdentityContextForToken(token, tokenHash, options);
}

async function recordAccountDeletionRequest(ctx, outcome) {
  const requestScope = outcome.localOnly ? 'local_test' : 'identity_service';
  await pool.execute(
    `
      INSERT INTO kq_account_deletion_requests (
        external_provider, external_user_id, status, request_scope, message, raw_request_json
      )
      VALUES (?, ?, ?, ?, ?, ?)
      ON DUPLICATE KEY UPDATE
        status = VALUES(status),
        request_scope = VALUES(request_scope),
        message = VALUES(message),
        raw_request_json = VALUES(raw_request_json),
        requested_at = NOW(),
        updated_at = NOW()
    `,
    [
      ctx.user.external_provider,
      ctx.user.external_user_id,
      outcome.status,
      requestScope,
      outcome.message,
      JSON.stringify({
        local_only: outcome.localOnly,
        user_id: ctx.user.id,
        requested_at: new Date().toISOString(),
      }),
    ],
  );
}

async function deleteLocalProjectAccount(userId) {
  await pool.execute('DELETE FROM kq_users WHERE id = ?', [userId]);
}

async function ensureDatabase() {
  assertIdentifier(config.db.database, 'KQ_DB_NAME');
  if (!envIsDisabled(process.env.KQ_DB_CREATE_DATABASE)) {
    const server = await mysql.createConnection({
      host: config.db.host,
      port: config.db.port,
      user: config.db.user,
      password: config.db.password,
      multipleStatements: false,
    });
    await server.query(
      `CREATE DATABASE IF NOT EXISTS \`${config.db.database}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`,
    );
    await server.end();
  }

  pool = mysql.createPool({
    host: config.db.host,
    port: config.db.port,
    user: config.db.user,
    password: config.db.password,
    database: config.db.database,
    waitForConnections: true,
    connectionLimit: Number.parseInt(process.env.KQ_DB_POOL_SIZE || '8', 10),
    namedPlaceholders: true,
    charset: 'utf8mb4',
  });

  await pool.query(`
    CREATE TABLE IF NOT EXISTS kq_users (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      external_provider VARCHAR(32) NOT NULL DEFAULT 'kunqiong',
      external_user_id VARCHAR(128) NOT NULL,
      username VARCHAR(128) NOT NULL,
      nickname VARCHAR(128) NOT NULL DEFAULT '',
      email VARCHAR(255) NOT NULL DEFAULT '',
      avatar_url TEXT NULL,
      token_hash CHAR(64) NULL,
      member_active TINYINT(1) NOT NULL DEFAULT 0,
      member_expire_at DATETIME NULL,
      raw_user_json JSON NULL,
      last_login_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uniq_external_user (external_provider, external_user_id),
      KEY idx_username (username),
      KEY idx_member_active (member_active)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS kq_connection_history (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      user_id BIGINT UNSIGNED NOT NULL,
      peer_id VARCHAR(128) NOT NULL,
      peer_alias VARCHAR(255) NOT NULL DEFAULT '',
      peer_username VARCHAR(255) NOT NULL DEFAULT '',
      peer_hostname VARCHAR(255) NOT NULL DEFAULT '',
      peer_platform VARCHAR(64) NOT NULL DEFAULT '',
      conn_type VARCHAR(32) NOT NULL DEFAULT 'remote',
      connect_count INT UNSIGNED NOT NULL DEFAULT 1,
      metadata JSON NULL,
      connected_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uniq_user_peer (user_id, peer_id),
      KEY idx_user_last_seen (user_id, last_seen_at),
      CONSTRAINT fk_history_user FOREIGN KEY (user_id) REFERENCES kq_users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS kq_account_devices (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      user_id BIGINT UNSIGNED NOT NULL,
      device_key VARCHAR(128) NOT NULL,
      device_id VARCHAR(128) NOT NULL,
      device_name VARCHAR(255) NOT NULL DEFAULT '',
      device_alias VARCHAR(255) NOT NULL DEFAULT '',
      device_hostname VARCHAR(255) NOT NULL DEFAULT '',
      device_platform VARCHAR(64) NOT NULL DEFAULT '',
      device_type VARCHAR(64) NOT NULL DEFAULT '',
      metadata JSON NULL,
      first_login_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_login_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_seen_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uniq_user_device_key (user_id, device_key),
      KEY idx_user_device_seen (user_id, last_seen_at),
      CONSTRAINT fk_account_device_user FOREIGN KEY (user_id) REFERENCES kq_users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
  await ensureAccountDeviceSchema();

  await pool.query(`
    CREATE TABLE IF NOT EXISTS kq_member_orders (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      user_id BIGINT UNSIGNED NOT NULL,
      order_no VARCHAR(64) NOT NULL,
      package_id INT UNSIGNED NOT NULL DEFAULT 0,
      package_name VARCHAR(128) NOT NULL DEFAULT '',
      package_days INT UNSIGNED NOT NULL DEFAULT 0,
      pay_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
      pay_type TINYINT UNSIGNED NOT NULL DEFAULT 0,
      pay_status TINYINT UNSIGNED NOT NULL DEFAULT 0,
      expire_at DATETIME NULL,
      raw_order_json JSON NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uniq_order_no (order_no),
      KEY idx_user_order (user_id, created_at),
      CONSTRAINT fk_order_user FOREIGN KEY (user_id) REFERENCES kq_users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS kq_member_snapshots (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      user_id BIGINT UNSIGNED NOT NULL,
      member_active TINYINT(1) NOT NULL DEFAULT 0,
      member_expire_at DATETIME NULL,
      subsite_name VARCHAR(255) NOT NULL DEFAULT '',
      package_count INT UNSIGNED NOT NULL DEFAULT 0,
      snapshot_hash CHAR(64) NOT NULL,
      raw_member_json JSON NULL,
      synced_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uniq_user_snapshot_hash (user_id, snapshot_hash),
      KEY idx_user_synced (user_id, synced_at),
      CONSTRAINT fk_snapshot_user FOREIGN KEY (user_id) REFERENCES kq_users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS kq_account_deletion_requests (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      external_provider VARCHAR(32) NOT NULL DEFAULT 'kunqiong',
      external_user_id VARCHAR(128) NOT NULL,
      status VARCHAR(32) NOT NULL DEFAULT 'pending',
      request_scope VARCHAR(32) NOT NULL DEFAULT 'identity_service',
      message VARCHAR(512) NOT NULL DEFAULT '',
      raw_request_json JSON NULL,
      requested_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uniq_deletion_external_user (external_provider, external_user_id),
      KEY idx_deletion_status (status, requested_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS kq_apple_transactions (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      transaction_id VARCHAR(128) NOT NULL,
      original_transaction_id VARCHAR(128) NOT NULL,
      user_id BIGINT UNSIGNED NOT NULL,
      package_id INT UNSIGNED NOT NULL DEFAULT 0,
      product_id VARCHAR(255) NOT NULL,
      environment VARCHAR(32) NOT NULL,
      expires_at DATETIME NULL,
      purchase_at DATETIME NULL,
      signed_transaction_hash CHAR(64) NOT NULL,
      raw_transaction_json JSON NULL,
      verified_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uniq_apple_transaction (transaction_id),
      KEY idx_apple_user_original (user_id, original_transaction_id),
      CONSTRAINT fk_apple_transaction_user FOREIGN KEY (user_id) REFERENCES kq_users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);

  await pool.query(`
    CREATE TABLE IF NOT EXISTS kq_apple_subscription_owners (
      original_transaction_id VARCHAR(128) NOT NULL,
      user_id BIGINT UNSIGNED NOT NULL,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (original_transaction_id),
      KEY idx_apple_subscription_owner_user (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
}

async function upsertUser(user) {
  const expireAt = normalizeDateTime(user.memberExpireAt);
  await pool.execute(
    `
      INSERT INTO kq_users (
        external_provider, external_user_id, username, nickname, email, avatar_url,
        token_hash, member_active, member_expire_at, raw_user_json, last_login_at, last_seen_at
      )
      VALUES ('kunqiong', ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())
      ON DUPLICATE KEY UPDATE
        username = VALUES(username),
        nickname = VALUES(nickname),
        email = VALUES(email),
        avatar_url = VALUES(avatar_url),
        token_hash = VALUES(token_hash),
        member_active = VALUES(member_active),
        member_expire_at = VALUES(member_expire_at),
        raw_user_json = VALUES(raw_user_json),
        last_seen_at = NOW()
    `,
    [
      user.externalUserId,
      user.username,
      user.nickname,
      user.email,
      user.avatarUrl,
      user.tokenHash,
      user.memberActive ? 1 : 0,
      expireAt,
      JSON.stringify(user.raw),
    ],
  );
  const [rows] = await pool.execute(
    'SELECT * FROM kq_users WHERE external_provider = ? AND external_user_id = ? LIMIT 1',
    ['kunqiong', user.externalUserId],
  );
  return rows[0];
}

async function upsertUserIdentity(user) {
  await pool.execute(
    `
      INSERT INTO kq_users (
        external_provider, external_user_id, username, nickname, email, avatar_url,
        token_hash, raw_user_json, last_login_at, last_seen_at
      )
      VALUES ('kunqiong', ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())
      ON DUPLICATE KEY UPDATE
        username = VALUES(username),
        nickname = VALUES(nickname),
        email = VALUES(email),
        avatar_url = VALUES(avatar_url),
        token_hash = VALUES(token_hash),
        raw_user_json = VALUES(raw_user_json),
        last_seen_at = NOW()
    `,
    [
      user.externalUserId,
      user.username,
      user.nickname,
      user.email,
      user.avatarUrl,
      user.tokenHash,
      JSON.stringify(user.raw),
    ],
  );
  const [rows] = await pool.execute(
    'SELECT * FROM kq_users WHERE external_provider = ? AND external_user_id = ? LIMIT 1',
    ['kunqiong', user.externalUserId],
  );
  return rows[0];
}

async function saveMemberSnapshot(user, memberInfo) {
  const packages = Array.isArray(memberInfo?.packages) ? memberInfo.packages : [];
  const snapshotJson = JSON.stringify(memberInfo ?? {});
  await pool.execute(
    `
      INSERT INTO kq_member_snapshots (
        user_id, member_active, member_expire_at, subsite_name, package_count,
        snapshot_hash, raw_member_json, synced_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, NOW())
      ON DUPLICATE KEY UPDATE
        member_active = VALUES(member_active),
        member_expire_at = VALUES(member_expire_at),
        subsite_name = VALUES(subsite_name),
        package_count = VALUES(package_count),
        raw_member_json = VALUES(raw_member_json),
        synced_at = NOW()
    `,
    [
      user.id,
      toBool(memberInfo?.web_member_active) ? 1 : 0,
      normalizeDateTime(memberInfo?.web_member_expire_at),
      String(memberInfo?.subsite_name || config.subsiteName),
      packages.length,
      sha256(snapshotJson),
      snapshotJson,
    ],
  );
}

async function mergeLegacyAccountRowsForUser(user, normalizedUser) {
  const nickname = String(normalizedUser?.mergeNickname || '').trim();
  if (!nickname) return;
  const [legacyUsers] = await pool.execute(
    `
      SELECT id
      FROM kq_users
      WHERE id <> ?
        AND external_provider = 'kunqiong'
        AND (
          JSON_UNQUOTE(JSON_EXTRACT(raw_user_json, '$.user_info.nickname')) = ?
          OR JSON_UNQUOTE(JSON_EXTRACT(raw_user_json, '$.nickname')) = ?
          OR JSON_UNQUOTE(JSON_EXTRACT(raw_user_json, '$.user.nickname')) = ?
        )
    `,
    [user.id, nickname, nickname, nickname],
  );
  const legacyUserIds = legacyUsers
    .map((row) => Number(row.id))
    .filter((id) => Number.isSafeInteger(id) && id > 0);
  if (!legacyUserIds.length) return;

  const [legacyDevices] = await pool.query(
    `
      SELECT
        device_key, device_id, device_name, device_alias, device_hostname,
        device_platform, device_type, metadata, first_login_at, last_login_at, last_seen_at
      FROM kq_account_devices
      WHERE user_id IN (?)
    `,
    [legacyUserIds],
  );
  for (const row of legacyDevices) {
    const metadata =
      row.metadata == null || typeof row.metadata === 'string'
        ? row.metadata
        : JSON.stringify(row.metadata);
    await pool.execute(
      `
        INSERT INTO kq_account_devices (
          user_id, device_key, device_id, device_name, device_alias, device_hostname,
          device_platform, device_type, metadata, first_login_at, last_login_at, last_seen_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
          device_id = VALUES(device_id),
          device_name = VALUES(device_name),
          device_alias = VALUES(device_alias),
          device_hostname = VALUES(device_hostname),
          device_platform = VALUES(device_platform),
          device_type = VALUES(device_type),
          metadata = VALUES(metadata),
          first_login_at = LEAST(first_login_at, VALUES(first_login_at)),
          last_login_at = GREATEST(last_login_at, VALUES(last_login_at)),
          last_seen_at = GREATEST(last_seen_at, VALUES(last_seen_at))
      `,
      [
        user.id,
        row.device_key || row.device_id || '',
        row.device_id || '',
        row.device_name || '',
        row.device_alias || row.device_name || '',
        row.device_hostname || row.device_name || '',
        row.device_platform || '',
        row.device_type || '',
        metadata,
        row.first_login_at,
        row.last_login_at,
        row.last_seen_at,
      ],
    );
  }
  await pool.query('DELETE FROM kq_account_devices WHERE user_id IN (?)', [
    legacyUserIds,
  ]);
}

function normalizeDateTime(value) {
  if (!value) return null;
  const text = String(value).trim();
  return /^\d{4}-\d{2}-\d{2}/.test(text) ? text : null;
}

function getClientIp(req) {
  const realIp = String(req.get('x-real-ip') || '').trim();
  if (realIp) return realIp;
  const forwarded = String(req.get('x-forwarded-for') || '')
    .split(',')[0]
    .trim();
  return forwarded || req.ip || req.socket?.remoteAddress || 'unknown';
}

function downloadClientState(ip) {
  const now = Date.now();
  const state = downloadLimiter.clients.get(ip) || {
    windowStart: now,
    requests: 0,
    active: 0,
  };
  if (now - state.windowStart > config.download.windowMs) {
    state.windowStart = now;
    state.requests = 0;
  }
  downloadLimiter.clients.set(ip, state);
  if (downloadLimiter.clients.size > 5000) {
    for (const [clientIp, clientState] of downloadLimiter.clients) {
      if (
        clientState.active === 0 &&
        now - clientState.windowStart > config.download.windowMs * 2
      ) {
        downloadLimiter.clients.delete(clientIp);
      }
    }
  }
  return state;
}

function acquireDownloadSlot(req, res) {
  const ip = getClientIp(req);
  const state = downloadClientState(ip);
  if (state.requests >= config.download.maxRequestsPerWindow) {
    const retryAfter = Math.max(
      1,
      Math.ceil((config.download.windowMs - (Date.now() - state.windowStart)) / 1000),
    );
    res.setHeader('retry-after', String(retryAfter));
    textError(res, 429, '当前下载人数较多，请稍后再试。');
    return null;
  }
  if (state.active >= config.download.maxPerIpConcurrent) {
    textError(res, 429, '当前下载任务较多，请稍后再试。');
    return null;
  }
  if (downloadLimiter.active >= config.download.maxGlobalConcurrent) {
    textError(res, 503, '当前下载人数较多，请稍后再试。');
    return null;
  }
  state.requests += 1;
  state.active += 1;
  downloadLimiter.active += 1;
  let released = false;
  return () => {
    if (released) return;
    released = true;
    state.active = Math.max(0, state.active - 1);
    downloadLimiter.active = Math.max(0, downloadLimiter.active - 1);
  };
}

function parseRangeHeader(rangeHeader, size) {
  if (!rangeHeader) return null;
  const match = /^bytes=(\d*)-(\d*)$/.exec(String(rangeHeader).trim());
  if (!match) return { invalid: true };
  const [, startText, endText] = match;
  if (!startText && !endText) return { invalid: true };
  let start;
  let end;
  if (!startText) {
    const suffixLength = Number.parseInt(endText, 10);
    if (!Number.isFinite(suffixLength) || suffixLength <= 0) {
      return { invalid: true };
    }
    start = Math.max(0, size - suffixLength);
    end = size - 1;
  } else {
    start = Number.parseInt(startText, 10);
    end = endText ? Number.parseInt(endText, 10) : size - 1;
  }
  if (
    !Number.isFinite(start) ||
    !Number.isFinite(end) ||
    start < 0 ||
    end < start ||
    start >= size
  ) {
    return { invalid: true };
  }
  return { start, end: Math.min(end, size - 1) };
}

async function sendDownloadFile(req, res, download, contentType) {
  const releaseDownload = req.method !== 'HEAD' ? acquireDownloadSlot(req, res) : () => {};
  if (!releaseDownload) return;
  try {
    const stat = await fs.promises.stat(download.filePath);
    if (!stat.isFile()) {
      releaseDownload();
      textError(res, 404, '安装包暂时不可用，请稍后再试。');
      return;
    }

    const range = parseRangeHeader(req.get('range'), stat.size);
    if (range?.invalid) {
      releaseDownload();
      res.setHeader('content-range', `bytes */${stat.size}`);
      textError(res, 416, '下载请求无效，请重新点击下载。');
      return;
    }

    const start = range ? range.start : 0;
    const end = range ? range.end : stat.size - 1;
    const contentLength = end - start + 1;
    const dispositionName = download.fileName.replace(/["\\]/g, '');
    const headers = {
      'accept-ranges': 'bytes',
      'cache-control': 'private, max-age=300',
      'content-type': contentType,
      'content-disposition': `attachment; filename="${dispositionName}"; filename*=UTF-8''${encodeURIComponent(download.fileName)}`,
      'content-length': String(contentLength),
      'x-kq-download-version': download.version,
    };
    if (download.sha256) {
      headers['x-kq-download-sha256'] = download.sha256;
    }
    if (range) {
      headers['content-range'] = `bytes ${start}-${end}/${stat.size}`;
    }
    res.writeHead(range ? 206 : 200, headers);
    if (req.method === 'HEAD') {
      releaseDownload();
      res.end();
      return;
    }

    const stream = fs.createReadStream(download.filePath, { start, end });
    const finish = () => releaseDownload();
    stream.on('error', (error) => {
      console.error(error);
      if (!res.headersSent) {
        textError(res, 500, '安装包暂时不可用，请稍后再试。');
      } else {
        res.destroy(error);
      }
      finish();
    });
    res.on('close', finish);
    res.on('finish', finish);
    stream.pipe(res);
  } catch (error) {
    releaseDownload();
    if (error?.code === 'ENOENT') {
      textError(res, 404, '安装包暂时不可用，请稍后再试。');
      return;
    }
    throw error;
  }
}

async function sendWindowsInstaller(req, res) {
  return sendDownloadFile(
    req,
    res,
    config.download,
    'application/vnd.microsoft.portable-executable',
  );
}

async function sendAndroidApk(req, res) {
  return sendDownloadFile(
    req,
    res,
    config.androidDownload,
    'application/vnd.android.package-archive',
  );
}

function htmlEscape(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function publicAssetUrl(req, assetPath) {
  const normalizedPath = String(assetPath || '').replace(/^\/+/, '');
  const configuredBase = String(config.publicApiUrl || '').trim();
  if (configuredBase) {
    return `${configuredBase.replace(/\/+$/, '')}/${normalizedPath}`;
  }
  const protocol = req?.protocol || 'http';
  const host = req?.get?.('host') || `localhost:${config.port}`;
  return `${protocol}://${host}/${normalizedPath}`;
}

function normalizeUriScheme(value) {
  const scheme = String(value || 'kqremote')
    .trim()
    .replace(/:.*$/, '')
    .toLowerCase();
  return /^[a-z][a-z0-9+.-]*$/.test(scheme) ? scheme : 'kqremote';
}

function formatInviteDeviceId(value) {
  const compact = String(value || '').replace(/\s+/g, '').trim();
  if (!compact) return '--- --- ---';
  return compact.replace(/(.{3})(?=.)/g, '$1 ');
}

function decodeInvitePayload(req) {
  const encoded = String(req.query?.i || '').trim();
  if (!encoded) return {};
  try {
    const json = Buffer.from(encoded, 'base64url').toString('utf8');
    const payload = JSON.parse(json);
    return payload && typeof payload === 'object' ? payload : {};
  } catch {
    return {};
  }
}

function invitePage(payload, req) {
  const id = String(payload.id || '').replace(/\s+/g, '').trim();
  const password = String(payload.password || '').trim();
  const ts = Number(payload.ts || 0);
  const createdAt = ts > 0 ? new Date(ts) : null;
  const isExpired =
    !id ||
    !password ||
    !createdAt ||
    Number.isNaN(createdAt.getTime()) ||
    Date.now() - createdAt.getTime() > 24 * 60 * 60 * 1000;
  const deepLink = `${config.appScheme}://connect/${encodeURIComponent(id)}?password=${encodeURIComponent(password)}`;
  const maskedPassword = password ? `${password.slice(0, 2)}${'*'.repeat(Math.max(password.length - 4, 2))}${password.slice(-2)}` : '--';
  const safeId = htmlEscape(formatInviteDeviceId(id));
  const safePassword = htmlEscape(maskedPassword);
  const safeCreatedAt = htmlEscape(
    createdAt && !Number.isNaN(createdAt.getTime())
      ? createdAt.toLocaleString('zh-CN', { hour12: false, timeZone: 'Asia/Shanghai' })
      : '--',
  );
  const safeIconUrl = htmlEscape(kqIconAssetPath);
  const safeIconAbsoluteUrl = htmlEscape(publicAssetUrl(req, kqIconAssetPath));
  const disabledAttr = isExpired ? 'disabled aria-disabled="true"' : '';
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>鲲穹远程协助邀请</title>
  <link rel="icon" type="image/png" href="${safeIconUrl}" />
  <link rel="apple-touch-icon" href="${safeIconUrl}" />
  <meta property="og:image" content="${safeIconAbsoluteUrl}" />
  <meta name="twitter:image" content="${safeIconAbsoluteUrl}" />
  <style>
    :root {
      color-scheme: light dark;
      --ink: #10243e;
      --muted: #5d7190;
      --primary: #1277d9;
      --line: rgba(119, 181, 230, .42);
      --panel: rgba(255, 255, 255, .82);
      --soft: rgba(234, 246, 255, .86);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      font-family: "Microsoft YaHei", "PingFang SC", system-ui, sans-serif;
      color: var(--ink);
      background:
        radial-gradient(circle at 14% 18%, rgba(103, 216, 234, .46), transparent 28rem),
        radial-gradient(circle at 84% 10%, rgba(167, 190, 255, .58), transparent 30rem),
        linear-gradient(135deg, #dff8ff 0%, #edf7ff 44%, #dfe7ff 100%);
      overflow: hidden;
    }
    body::before {
      content: "";
      position: fixed;
      inset: auto -9rem -14rem auto;
      width: 48rem;
      height: 48rem;
      border-radius: 9rem;
      transform: rotate(18deg);
      background: linear-gradient(145deg, rgba(52, 156, 232, .12), rgba(114, 123, 232, .08));
      border: 1px solid rgba(255, 255, 255, .42);
    }
    main {
      position: relative;
      width: min(460px, calc(100vw - 32px));
      padding: 32px;
      border: 1px solid rgba(255, 255, 255, .72);
      border-radius: 16px;
      background: var(--panel);
      box-shadow: 0 28px 80px rgba(15, 42, 72, .18);
      backdrop-filter: blur(18px);
    }
    .brand { display: flex; align-items: center; justify-content: center; gap: 12px; margin-bottom: 26px; }
    .brand-icon {
      width: 44px;
      height: 44px;
      border-radius: 14px;
      display: block;
      box-shadow: 0 14px 30px rgba(18, 119, 217, .24);
    }
    h1 { margin: 0; font-size: 26px; letter-spacing: 0; }
    .subtitle { margin: 0 0 18px; text-align: center; color: var(--muted); font-weight: 700; }
    .info {
      border: 1px solid var(--line);
      border-radius: 12px;
      background: rgba(255,255,255,.62);
      padding: 14px 16px;
      margin-bottom: 22px;
    }
    .row { display: flex; justify-content: space-between; gap: 18px; padding: 8px 0; color: var(--muted); }
    .row strong { color: var(--ink); font-family: ui-monospace, SFMono-Regular, Consolas, monospace; letter-spacing: .02em; }
    .actions { display: grid; gap: 10px; }
    .wechat-tip {
      display: none;
      margin: -4px 0 16px;
      padding: 12px 14px;
      border: 1px solid rgba(18, 119, 217, .22);
      border-radius: 12px;
      color: var(--ink);
      background: rgba(18, 119, 217, .08);
      font-size: 13px;
      font-weight: 700;
      line-height: 1.7;
    }
    .wechat-tip strong { color: var(--primary); }
    button, a.button {
      width: 100%;
      height: 42px;
      border-radius: 9px;
      border: 1px solid transparent;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      text-decoration: none;
      font-size: 15px;
      font-weight: 800;
      cursor: pointer;
    }
    button.primary { color: #fff; background: linear-gradient(135deg, #1686e8, #0f66c2); box-shadow: 0 12px 28px rgba(18, 119, 217, .25); }
    button.primary:disabled { cursor: not-allowed; color: #f8fbff; background: #b9c2cc; box-shadow: none; }
    button.secondary { color: var(--ink); background: rgba(255,255,255,.72); border-color: rgba(16, 36, 62, .14); }
    a.button { color: var(--ink); background: #fff; border-color: rgba(16, 36, 62, .14); }
    .status { min-height: 24px; margin-top: 18px; text-align: center; color: ${isExpired ? '#e23b2e' : '#5d7190'}; font-size: 14px; font-weight: 700; }
    @media (prefers-color-scheme: dark) {
      :root { --ink: #e8f2ff; --muted: #9bb6d3; --panel: rgba(18, 29, 43, .86); --soft: rgba(30,48,69,.86); --line: rgba(76, 137, 184, .5); }
      body { background: linear-gradient(135deg, #102033 0%, #14283d 45%, #1d274a 100%); }
      .info { background: rgba(15, 26, 40, .68); }
      .wechat-tip { background: rgba(18, 119, 217, .14); border-color: rgba(95, 170, 235, .32); }
      button.secondary { background: rgba(255,255,255,.08); color: var(--ink); border-color: rgba(160, 205, 244, .2); }
      a.button { background: rgba(255,255,255,.08); color: var(--ink); border-color: rgba(160, 205, 244, .2); }
    }
  </style>
</head>
<body>
  <main>
    <section class="brand">
      <img class="brand-icon" src="${safeIconUrl}" alt="" />
      <h1>鲲穹远程桌面</h1>
    </section>
    <p class="subtitle">邀请你进行远程协助</p>
    <section class="info">
      <div class="row"><span>设备 ID</span><strong>${safeId}</strong></div>
      <div class="row"><span>设备验证码</span><strong>${safePassword}</strong></div>
      <div class="row"><span>邀请时间</span><strong>${safeCreatedAt}</strong></div>
      <div class="row"><span>有效期</span><strong>24 小时</strong></div>
    </section>
    <div class="wechat-tip" id="wechatTip">当前在微信内置浏览器中，微信会拦截直接打开客户端。请点击右上角 <strong>...</strong>，选择 <strong>在浏览器打开</strong> 后再点“开始远控”。</div>
    <section class="actions">
      <button class="primary" id="openApp" ${disabledAttr}>开始远控</button>
      <button class="secondary" id="copyLink" ${disabledAttr}>复制启动链接</button>
      <a class="button" href="download" rel="noopener">下载鲲穹远程桌面</a>
    </section>
    <div class="status" id="status">${isExpired ? '此链接已失效' : ''}</div>
  </main>
  <script>
    const deepLink = ${JSON.stringify(deepLink)};
    const expired = ${JSON.stringify(isExpired)};
    const isWeChat = /MicroMessenger/i.test(navigator.userAgent || '');
    const status = document.getElementById('status');
    const wechatTip = document.getElementById('wechatTip');
    const copyLinkButton = document.getElementById('copyLink');
    if (isWeChat && !expired) {
      wechatTip.style.display = 'block';
      status.textContent = '微信内置浏览器限制直接唤起客户端，请在外部浏览器打开此页面。';
    }
    async function copyDeepLink() {
      if (expired) return;
      try {
        if (navigator.clipboard && window.isSecureContext) {
          await navigator.clipboard.writeText(deepLink);
        } else {
          const input = document.createElement('textarea');
          input.value = deepLink;
          input.setAttribute('readonly', 'readonly');
          input.style.position = 'fixed';
          input.style.left = '-9999px';
          document.body.appendChild(input);
          input.select();
          document.execCommand('copy');
          document.body.removeChild(input);
        }
        status.textContent = '启动链接已复制。请在外部浏览器地址栏打开，或安装客户端后再使用。';
      } catch (_) {
        status.textContent = '复制失败，请点击右上角在浏览器打开后重试。';
      }
    }
    document.getElementById('openApp').addEventListener('click', () => {
      if (expired) return;
      if (isWeChat) {
        status.textContent = '微信拦截了客户端唤起，请点击右上角 ... 选择“在浏览器打开”。';
        copyDeepLink();
        return;
      }
      status.textContent = '正在打开鲲穹远程桌面...';
      window.location.href = deepLink;
      window.setTimeout(() => {
        status.textContent = '如果没有自动打开，请确认已安装客户端；仍打不开时可复制启动链接或点击下载按钮。';
      }, 1500);
    });
    copyLinkButton.addEventListener('click', copyDeepLink);
  </script>
</body>
</html>`;
}

function downloadPage(req) {
  const safeWindowsDownloadUrl = htmlEscape(config.downloadUrl);
  const safeAndroidDownloadUrl = htmlEscape(config.androidDownloadUrl);
  const safeOfficialUrl = htmlEscape('https://kunqiongai.com/');
  const safeWindowsVersion = htmlEscape(config.download.version);
  const safeAndroidVersion = htmlEscape(config.androidDownload.version);
  const safeIconUrl = htmlEscape(kqIconAssetPath);
  const safeIconAbsoluteUrl = htmlEscape(publicAssetUrl(req, kqIconAssetPath));
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>下载鲲穹远程桌面</title>
  <link rel="icon" type="image/png" href="${safeIconUrl}" />
  <link rel="apple-touch-icon" href="${safeIconUrl}" />
  <meta property="og:image" content="${safeIconAbsoluteUrl}" />
  <meta name="twitter:image" content="${safeIconAbsoluteUrl}" />
  <style>
    :root {
      color-scheme: light dark;
      --ink: #102338;
      --muted: #60758d;
      --primary: #0f82df;
      --primary-2: #1166c2;
      --line: rgba(79, 153, 214, .28);
      --panel: rgba(255, 255, 255, .84);
      --soft: rgba(235, 247, 255, .74);
      --accent: #28c7d8;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: "Microsoft YaHei", "PingFang SC", system-ui, sans-serif;
      color: var(--ink);
      background:
        linear-gradient(115deg, rgba(255,255,255,.88), rgba(255,255,255,0) 42%),
        radial-gradient(circle at 14% 18%, rgba(74, 210, 229, .36), transparent 28rem),
        radial-gradient(circle at 88% 8%, rgba(92, 151, 243, .38), transparent 30rem),
        linear-gradient(135deg, #eaf8ff 0%, #f6fbff 48%, #e9f0ff 100%);
    }
    .shell {
      width: min(1120px, calc(100vw - 36px));
      margin: 0 auto;
      padding: 28px 0 38px;
    }
    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 18px;
      margin-bottom: 44px;
    }
    .brand { display: flex; align-items: center; gap: 12px; font-weight: 900; font-size: 19px; }
    .brand-icon {
      width: 42px;
      height: 42px;
      border-radius: 12px;
      display: block;
      box-shadow: 0 14px 30px rgba(20, 124, 222, .24);
    }
    .official {
      color: var(--muted);
      text-decoration: none;
      font-weight: 800;
      padding: 10px 14px;
      border: 1px solid var(--line);
      border-radius: 9px;
      background: rgba(255,255,255,.52);
    }
    main {
      display: grid;
      grid-template-columns: minmax(0, 1.04fr) minmax(340px, .96fr);
      gap: 36px;
      align-items: center;
    }
    .eyebrow {
      display: inline-flex;
      align-items: center;
      height: 32px;
      padding: 0 12px;
      border-radius: 999px;
      color: #0f65bf;
      background: rgba(225, 244, 255, .86);
      border: 1px solid rgba(55, 154, 222, .22);
      font-size: 13px;
      font-weight: 900;
      margin-bottom: 18px;
    }
    .hero h1 {
      margin: 0 0 16px;
      font-size: clamp(36px, 5.2vw, 62px);
      line-height: 1.04;
      letter-spacing: 0;
    }
    .hero p {
      max-width: 560px;
      margin: 0;
      color: var(--muted);
      font-size: 17px;
      line-height: 1.7;
      font-weight: 700;
    }
    .highlights {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;
      margin-top: 28px;
      max-width: 620px;
    }
    .highlight {
      min-height: 94px;
      padding: 16px;
      border-radius: 14px;
      background: rgba(255, 255, 255, .54);
      border: 1px solid var(--line);
    }
    .highlight strong { display: block; margin-bottom: 8px; font-size: 16px; }
    .highlight span { display: block; color: var(--muted); font-size: 13px; line-height: 1.5; font-weight: 700; }
    .panel {
      border: 1px solid rgba(255,255,255,.72);
      border-radius: 18px;
      padding: 28px;
      background: var(--panel);
      box-shadow: 0 30px 84px rgba(15, 42, 72, .16);
      backdrop-filter: blur(18px);
    }
    .panel h2 { margin: 0 0 10px; font-size: 28px; letter-spacing: 0; }
    .panel .desc { margin: 0 0 24px; color: var(--muted); line-height: 1.65; font-weight: 700; }
    .downloads {
      display: grid;
      gap: 12px;
      margin-bottom: 22px;
    }
    .download {
      width: 100%;
      min-height: 50px;
      padding: 0 18px;
      border: 0;
      border-radius: 12px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      color: white;
      text-decoration: none;
      font-size: 16px;
      font-weight: 900;
      background: linear-gradient(135deg, var(--primary), var(--primary-2));
      box-shadow: 0 14px 30px rgba(20, 124, 222, .28);
    }
    .download.android {
      color: var(--ink);
      background: rgba(255,255,255,.68);
      border: 1px solid var(--line);
      box-shadow: none;
    }
    .steps {
      display: grid;
      gap: 12px;
      margin: 24px 0 0;
      padding: 0;
      list-style: none;
    }
    .steps li {
      display: grid;
      grid-template-columns: 34px minmax(0, 1fr);
      gap: 12px;
      align-items: start;
      padding: 14px;
      border-radius: 12px;
      border: 1px solid var(--line);
      background: rgba(255,255,255,.52);
    }
    .step-no {
      width: 34px;
      height: 34px;
      display: grid;
      place-items: center;
      border-radius: 11px;
      color: #fff;
      background: linear-gradient(135deg, var(--accent), var(--primary));
      font-weight: 900;
    }
    .steps strong { display: block; margin: 0 0 4px; font-size: 15px; }
    .steps span { color: var(--muted); font-size: 13px; line-height: 1.5; font-weight: 700; }
    .version { margin: 18px 0 0; color: var(--muted); font-size: 12px; text-align: center; font-weight: 700; }
    @media (prefers-color-scheme: dark) {
      :root { --ink: #e8f2ff; --muted: #9bb6d3; --panel: rgba(18, 29, 43, .88); --soft: rgba(30,48,69,.86); --line: rgba(76, 137, 184, .48); }
      body { background: linear-gradient(135deg, #102033 0%, #14283d 45%, #1d274a 100%); }
      .official, .highlight, .steps li { background: rgba(255,255,255,.08); }
      .download.android { background: rgba(255,255,255,.08); color: var(--ink); }
      .eyebrow { color: #9ed9ff; background: rgba(40, 102, 156, .24); }
    }
    @media (max-width: 760px) {
      header { margin-bottom: 34px; }
      main { grid-template-columns: 1fr; }
      .hero h1 { font-size: 40px; }
      .highlights { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <div class="shell">
    <header>
      <div class="brand"><img class="brand-icon" src="${safeIconUrl}" alt="" /><span>鲲穹远程桌面</span></div>
      <a class="official" href="${safeOfficialUrl}" rel="noopener">公司官网</a>
    </header>
    <main>
      <section class="hero">
        <div class="eyebrow">鲲穹远程协助</div>
        <h1>安全连接，轻松完成远程协助</h1>
        <p>鲲穹远程桌面适用于临时协助、跨设备办公和售后支持。安装完成后，即可通过邀请链接快速发起连接。</p>
        <div class="highlights">
          <div class="highlight"><strong>快速协助</strong><span>打开邀请链接即可进入连接流程。</span></div>
          <div class="highlight"><strong>清晰流畅</strong><span>会员可使用更高清晰度与更高帧率。</span></div>
          <div class="highlight"><strong>企业可用</strong><span>适合办公支持、设备维护和客户服务。</span></div>
        </div>
      </section>
      <section class="panel">
        <h2>客户端下载</h2>
        <p class="desc">选择当前设备对应的版本。安装完成后，回到邀请页面点击“开始远控”，即可自动打开客户端并继续连接。</p>
        <div class="downloads">
          <a class="download" href="${safeWindowsDownloadUrl}" rel="noopener">下载 Windows 安装包</a>
          <a class="download android" href="${safeAndroidDownloadUrl}" rel="noopener">下载 Android 安装包</a>
        </div>
        <ol class="steps">
          <li><span class="step-no">1</span><div><strong>下载安装</strong><span>运行安装包并按照向导完成安装。</span></div></li>
          <li><span class="step-no">2</span><div><strong>打开邀请链接</strong><span>回到协助邀请页面，点击“开始远控”。</span></div></li>
          <li><span class="step-no">3</span><div><strong>开始协助</strong><span>确认连接信息后即可进入远程桌面。</span></div></li>
        </ol>
        <p class="version">Windows ${safeWindowsVersion} · Android ${safeAndroidVersion}</p>
      </section>
    </main>
  </div>
</body>
</html>`;
}

function privacyPolicyPage() {
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <meta name="robots" content="index,follow" />
  <title>鲲穹远程桌面隐私政策</title>
  <style>
    :root { color-scheme: light; --ink: #172b45; --muted: #5f7185; --line: #d9e2ec; --link: #0b74c9; }
    * { box-sizing: border-box; }
    body { margin: 0; background: #f6f8fb; color: var(--ink); font-family: "Microsoft YaHei", "PingFang SC", system-ui, sans-serif; line-height: 1.7; }
    main { width: min(860px, calc(100% - 32px)); margin: 0 auto; padding: 42px 0 64px; }
    header { margin-bottom: 34px; border-bottom: 1px solid var(--line); padding-bottom: 24px; }
    h1 { margin: 0 0 10px; font-size: 30px; letter-spacing: 0; }
    header p, .intro { margin: 0; color: var(--muted); }
    section { padding: 22px 0; border-bottom: 1px solid var(--line); }
    h2 { margin: 0 0 12px; font-size: 20px; letter-spacing: 0; }
    h2 span { color: var(--muted); font-weight: 500; font-size: 15px; }
    p { margin: 10px 0; }
    .english { color: var(--muted); font-size: 15px; }
    a { color: var(--link); }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>鲲穹远程桌面隐私政策</h1>
      <p>Kunqiong Remote Link Privacy Policy</p>
    </header>
    <p class="intro">本政策说明我们如何处理账号、远程协助和会员服务相关的数据。</p>
    <section>
      <h2>我们收集的数据 <span>Data we collect</span></h2>
      <p>为了创建和保护账号，我们会处理用户名、手机号、登录凭证和账号资料。</p>
      <p>为了提供远程协助，我们会处理设备识别信息、连接识别码、远程画面、输入操作，以及您主动选择传输的应用声音、语音、文件和剪贴板内容。</p>
      <p class="english">To create and protect an account, we process your username, phone number, sign-in credentials, and account profile. To provide remote assistance, we process device and connection identifiers, remote display frames, input actions, and the application audio, voice data, files, and clipboard content you choose to transmit.</p>
    </section>
    <section>
      <h2>数据如何使用 <span>How we use data</span></h2>
      <p>这些数据仅用于登录验证、建立远程连接、传输您发起的内容、保障服务安全、处理会员权益和提供技术支持。我们不会将您的个人数据用于跨应用跟踪，也不会出售您的个人数据。</p>
      <p class="english">We use this data only to authenticate you, establish remote sessions, transfer content you initiate, protect service security, process membership entitlements, and provide support. We do not use personal data for cross-app tracking or sell personal data.</p>
    </section>
    <section>
      <h2>数据共享与安全 <span>Data sharing and security</span></h2>
      <p>远程画面、应用声音、语音、控制指令、文件和剪贴板内容只会按您的操作发送给当前远程会话的另一端。我们仅在提供服务、安全防护、支付验证或法律要求所必需的范围内，与受约束的服务提供方处理数据。</p>
      <p class="english">Remote display frames, application audio, voice content, control instructions, files, and clipboard data are sent only to the other side of the remote session you start. We process data with bound service providers only when necessary to provide the service, protect security, verify payment, or comply with law.</p>
    </section>
    <section>
      <h2>保存、删除与您的选择 <span>Retention, deletion, and your choices</span></h2>
      <p>我们会在提供服务和履行法律义务所需的期限内保存账号和服务数据。您可以在系统设置中管理麦克风、照片和文件等权限，也可以随时退出登录。</p>
      <p>您可以在个人中心发起账号注销。注销会删除账号和不再需要保留的相关数据；法律要求保留的数据会在法定期限届满后删除。</p>
      <p class="english">We retain account and service data only for the period needed to provide the service and meet legal obligations. You can manage permissions in system settings, sign out at any time, and initiate account deletion from Personal center.</p>
    </section>
    <section>
      <h2>会员与支付 <span>Membership and payments</span></h2>
      <p>App Store 版本的会员购买和恢复购买由 Apple 的应用内购买完成。我们仅处理验证会员权益所需的交易信息。删除账号不会自动取消 Apple 订阅；如有自动续订订阅，请先在 Apple 订阅管理中取消。</p>
      <p class="english">Membership purchase and restoration in the App Store build are handled by Apple In-App Purchase. We process only transaction information needed to verify membership entitlements. Deleting an account does not automatically cancel an Apple subscription.</p>
    </section>
    <section>
      <h2>联系我们 <span>Contact us</span></h2>
      <p>如需咨询隐私、数据访问、更正或删除，请通过应用内“联系我们”渠道提交请求。本政策会在功能或数据处理方式发生重大变化时更新。</p>
      <p class="english">For privacy, data-access, correction, or deletion requests, use the Contact us channel in the app. We update this policy when there are material changes to features or data handling.</p>
    </section>
  </main>
</body>
</html>`;
}

function connectionLimitFor(user) {
  return Number(user.member_active) === 1 ? 50 : 5;
}

function normalizePeer(input) {
  const source = input?.peer && typeof input.peer === 'object' ? input.peer : input;
  const peerId = String(source?.peer_id ?? source?.id ?? '').trim();
  if (!peerId) {
    throw Object.assign(new Error('peer_id is required'), { statusCode: 400 });
  }
  return {
    peerId,
    alias: String(source?.peer_alias ?? source?.alias ?? ''),
    username: String(source?.peer_username ?? source?.username ?? ''),
    hostname: String(source?.peer_hostname ?? source?.hostname ?? ''),
    platform: String(source?.peer_platform ?? source?.platform ?? ''),
    connType: String(source?.conn_type ?? source?.connType ?? 'remote'),
    metadata: source?.metadata ?? source ?? {},
  };
}

async function tableColumnExists(tableName, columnName) {
  const [rows] = await pool.execute(
    `
      SELECT 1
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = ?
        AND COLUMN_NAME = ?
      LIMIT 1
    `,
    [tableName, columnName],
  );
  return rows.length > 0;
}

async function tableIndexExists(tableName, indexName) {
  const [rows] = await pool.execute(
    `
      SELECT 1
      FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = ?
        AND INDEX_NAME = ?
      LIMIT 1
    `,
    [tableName, indexName],
  );
  return rows.length > 0;
}

async function ensureAccountDeviceSchema() {
  if (!(await tableColumnExists('kq_account_devices', 'device_key'))) {
    await pool.query(`
      ALTER TABLE kq_account_devices
      ADD COLUMN device_key VARCHAR(128) NOT NULL DEFAULT '' AFTER user_id
    `);
  }
  await pool.query(`
    UPDATE kq_account_devices
    SET device_key = device_id
    WHERE device_key = ''
  `);
  if (await tableIndexExists('kq_account_devices', 'uniq_user_device')) {
    await pool.query('ALTER TABLE kq_account_devices DROP INDEX uniq_user_device');
  }
  if (!(await tableIndexExists('kq_account_devices', 'uniq_user_device_key'))) {
    await pool.query(`
      ALTER TABLE kq_account_devices
      ADD UNIQUE KEY uniq_user_device_key (user_id, device_key)
    `);
  }
}

function normalizeAccountDevice(input) {
  const source = input?.device && typeof input.device === 'object' ? input.device : input;
  const deviceId = String(source?.device_id ?? source?.peer_id ?? source?.id ?? '').trim();
  if (!deviceId) {
    throw Object.assign(new Error('device_id is required'), { statusCode: 400 });
  }
  const deviceKey = String(
    source?.device_key ??
      source?.login_device_id ??
      source?.account_device_key ??
      source?.uuid ??
      deviceId,
  ).trim();
  const deviceName = String(source?.device_name ?? source?.name ?? '').trim();
  const alias = String(source?.device_alias ?? source?.alias ?? deviceName);
  const hostname = String(source?.device_hostname ?? source?.hostname ?? deviceName);
  return {
    deviceKey: deviceKey || deviceId,
    deviceId,
    name: deviceName,
    alias,
    hostname,
    platform: String(source?.device_platform ?? source?.platform ?? ''),
    type: String(source?.device_type ?? source?.type ?? ''),
    metadata: source?.metadata ?? source ?? {},
  };
}

function accountDeviceIdentityNames(device) {
  return [
    device.name,
    device.hostname,
    device.alias,
  ]
    .map((value) => String(value || '').trim())
    .filter(Boolean)
    .filter((value, index, values) => values.indexOf(value) === index);
}

async function savePeerHistory(user, peer) {
  await pool.execute(
    `
      INSERT INTO kq_connection_history (
        user_id, peer_id, peer_alias, peer_username, peer_hostname, peer_platform,
        conn_type, metadata, connected_at, last_seen_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())
      ON DUPLICATE KEY UPDATE
        peer_alias = VALUES(peer_alias),
        peer_username = VALUES(peer_username),
        peer_hostname = VALUES(peer_hostname),
        peer_platform = VALUES(peer_platform),
        conn_type = VALUES(conn_type),
        metadata = VALUES(metadata),
        connect_count = connect_count + 1,
        last_seen_at = NOW()
    `,
    [
      user.id,
      peer.peerId,
      peer.alias,
      peer.username,
      peer.hostname,
      peer.platform,
      peer.connType,
      JSON.stringify(peer.metadata),
    ],
  );
  await trimPeerHistory(user);
}

async function saveAccountDevice(user, device) {
  await pool.execute(
    `
      INSERT INTO kq_account_devices (
        user_id, device_key, device_id, device_name, device_alias, device_hostname,
        device_platform, device_type, metadata, first_login_at, last_login_at, last_seen_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW(), NOW())
      ON DUPLICATE KEY UPDATE
        device_id = VALUES(device_id),
        device_name = VALUES(device_name),
        device_alias = VALUES(device_alias),
        device_hostname = VALUES(device_hostname),
        device_platform = VALUES(device_platform),
        device_type = VALUES(device_type),
        metadata = VALUES(metadata),
        last_login_at = NOW(),
        last_seen_at = NOW()
    `,
    [
      user.id,
      device.deviceKey,
      device.deviceId,
      device.name,
      device.alias,
      device.hostname,
      device.platform,
      device.type,
      JSON.stringify(device.metadata),
    ],
  );
  await deleteLegacyAccountDeviceRows(user, device);
  await deleteSupersededAccountDeviceRows(user, device);
}

async function deleteLegacyAccountDeviceRows(user, device) {
  await pool.execute(
    `
      DELETE FROM kq_account_devices
      WHERE user_id = ?
        AND device_id = ?
        AND device_key = device_id
        AND device_key <> ?
    `,
    [user.id, device.deviceId, device.deviceKey],
  );
}

async function deleteSupersededAccountDeviceRows(user, device) {
  const platform = String(device.platform || '').trim();
  const names = accountDeviceIdentityNames(device);
  if (!platform || !names.length) return;

  await pool.query(
    `
      DELETE FROM kq_account_devices
      WHERE user_id = ?
        AND device_key <> ?
        AND LOWER(device_platform) = LOWER(?)
        AND (
          device_name IN (?)
          OR device_hostname IN (?)
          OR device_alias IN (?)
        )
    `,
    [user.id, device.deviceKey, platform, names, names, names],
  );
}

async function trimPeerHistory(user) {
  const limit = connectionLimitFor(user);
  const [rows] = await pool.execute(
    `
      SELECT id
      FROM kq_connection_history
      WHERE user_id = ?
      ORDER BY last_seen_at DESC, id DESC
      LIMIT 100000 OFFSET ${limit}
    `,
    [user.id],
  );
  if (!rows.length) return;
  await pool.query('DELETE FROM kq_connection_history WHERE id IN (?)', [
    rows.map((row) => row.id),
  ]);
}

function mapHistoryRow(row) {
  return {
    id: row.peer_id,
    alias: row.peer_alias || '',
    username: row.peer_username || '',
    hostname: row.peer_hostname || '',
    platform: row.peer_platform || '',
    conn_type: row.conn_type || 'remote',
    connect_count: row.connect_count,
    last_seen_at: row.last_seen_at,
  };
}

function mapAccountDeviceRow(row) {
  return {
    id: row.device_id,
    device_key: row.device_key || '',
    alias: row.device_alias || row.device_name || '',
    username: '',
    hostname: row.device_hostname || row.device_name || '',
    platform: row.device_platform || '',
    device_type: row.device_type || '',
    last_login_at: row.last_login_at,
    last_seen_at: row.last_seen_at,
  };
}

const app = express();
const requestGate = createRequestGate(config.requestGate);
app.disable('x-powered-by');
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: false }));
app.use(
  ['/assets', '/api/assets', '/kq-api/assets'],
  express.static(path.resolve(__dirname, '../public/assets'), {
    immutable: true,
    maxAge: '7d',
  }),
);
app.use((req, res, next) => {
  res.setHeader('access-control-allow-origin', '*');
  res.setHeader('access-control-allow-methods', 'GET,POST,OPTIONS');
  res.setHeader(
    'access-control-allow-headers',
    'authorization,content-type,token,x-kq-token,x-kq-admin-token,x-admin-token',
  );
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }
  next();
});

app.get(
  ['/admin/request-gate', '/api/admin/request-gate'],
  requestGate.requireAdmin,
  requestGate.handleGet,
);

app.post(
  ['/admin/request-gate', '/api/admin/request-gate'],
  requestGate.requireAdmin,
  requestGate.handlePost,
);

app.use(requestGate.middleware);

app.get(['/health', '/api/health'], async (_req, res, next) => {
  try {
    await pool.query('SELECT 1');
    res.json({
      ok: true,
      service: 'kq-remote-link-api',
      public_api_url: config.publicApiUrl,
      time: new Date().toISOString(),
    });
  } catch (error) {
    next(error);
  }
});

app.get(['/invite', '/api/invite'], (req, res) => {
  res
    .status(200)
    .type('html')
    .send(invitePage(decodeInvitePayload(req), req));
});

app.get(['/download', '/api/download'], (req, res) => {
  res
    .status(200)
    .type('html')
    .send(downloadPage(req));
});

app.get(['/privacy', '/api/privacy'], (_req, res) => {
  res.status(200).type('html').send(privacyPolicyPage());
});

app.head(['/download/windows', '/api/download/windows'], async (req, res, next) => {
  try {
    await sendWindowsInstaller(req, res);
  } catch (error) {
    next(error);
  }
});

app.get(['/download/windows', '/api/download/windows'], async (req, res, next) => {
  try {
    await sendWindowsInstaller(req, res);
  } catch (error) {
    next(error);
  }
});

app.head(['/download/android', '/api/download/android'], async (req, res, next) => {
  try {
    await sendAndroidApk(req, res);
  } catch (error) {
    next(error);
  }
});

app.get(['/download/android', '/api/download/android'], async (req, res, next) => {
  try {
    await sendAndroidApk(req, res);
  } catch (error) {
    next(error);
  }
});

app.get('/api/me', async (req, res, next) => {
  try {
    const ctx = await loadUserContext(req);
    res.json({
      ok: true,
      user: {
        id: ctx.user.id,
        username: ctx.user.username,
        nickname: ctx.user.nickname,
        email: ctx.user.email,
        avatar_url: ctx.user.avatar_url,
        member_active: Boolean(ctx.user.member_active),
        member_expire_at: ctx.user.member_expire_at,
      },
      member: ctx.memberInfo,
    });
  } catch (error) {
    next(error);
  }
});

app.get('/api/account-devices', async (req, res, next) => {
  try {
    const ctx = await loadUserIdentityContext(req);
    const [rows] = await pool.execute(
      `
        SELECT *
        FROM kq_account_devices
        WHERE user_id = ?
        ORDER BY last_seen_at DESC, id DESC
      `,
      [ctx.user.id],
    );
    res.json({ ok: true, items: rows.map(mapAccountDeviceRow) });
  } catch (error) {
    next(error);
  }
});

app.post('/api/account-devices/current', async (req, res, next) => {
  try {
    const ctx = await loadUserIdentityContext(req);
    const device = normalizeAccountDevice(req.body);
    await saveAccountDevice(ctx.user, device);
    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

app.get('/api/connection-history', async (req, res, next) => {
  try {
    const ctx = await loadUserIdentityContext(req);
    const limit = connectionLimitFor(ctx.user);
    const [rows] = await pool.execute(
      `
        SELECT *
        FROM kq_connection_history
        WHERE user_id = ?
        ORDER BY last_seen_at DESC, id DESC
        LIMIT ?
      `,
      [ctx.user.id, limit],
    );
    res.json({ ok: true, limit, items: rows.map(mapHistoryRow) });
  } catch (error) {
    next(error);
  }
});

app.post('/api/connection-history', async (req, res, next) => {
  try {
    const ctx = await loadUserIdentityContext(req);
    const peer = normalizePeer(req.body);
    await savePeerHistory(ctx.user, peer);
    const limit = connectionLimitFor(ctx.user);
    res.json({ ok: true, limit });
  } catch (error) {
    next(error);
  }
});

app.delete('/api/connection-history/:peerId', async (req, res, next) => {
  try {
    const ctx = await loadUserIdentityContext(req);
    const peerId = String(req.params.peerId || '').trim();
    if (!peerId) {
      throw Object.assign(new Error('peer_id is required'), { statusCode: 400 });
    }
    const [result] = await pool.execute(
      'DELETE FROM kq_connection_history WHERE user_id = ? AND peer_id = ?',
      [ctx.user.id, peerId],
    );
    res.json({ ok: true, deleted: result.affectedRows || 0 });
  } catch (error) {
    next(error);
  }
});

app.post('/api/connection-history/bulk', async (req, res, next) => {
  try {
    const ctx = await loadUserIdentityContext(req);
    const peers = Array.isArray(req.body?.peers) ? req.body.peers : [];
    for (const item of peers.slice(0, connectionLimitFor(ctx.user))) {
      await savePeerHistory(ctx.user, normalizePeer(item));
    }
    const limit = connectionLimitFor(ctx.user);
    res.json({ ok: true, limit, stored: Math.min(peers.length, limit) });
  } catch (error) {
    next(error);
  }
});

app.post(['/api/auth/account/delete', '/api/account/delete'], async (req, res, next) => {
  try {
    const token = getAuthToken(req);
    const ctx = await loadUserIdentityContext(req, { allowPendingDeletion: true });
    const outcome = await submitAccountDeletion({
      mode: config.accountDeletion.mode,
      upstreamUrl: config.accountDeletion.upstreamUrl,
      token,
      confirmation: req.body?.confirmation,
    });
    await recordAccountDeletionRequest(ctx, outcome);
    await deleteLocalProjectAccount(ctx.user.id);
    clearCachedIdentityContext(sha256(token));
    res.status(outcome.statusCode).json({
      success: true,
      code: outcome.statusCode,
      status: outcome.status,
      message: outcome.localOnly
        ? '测试环境已清理本项目数据，登录账号不会在测试环境中删除。'
        : outcome.message,
      test_only: outcome.localOnly,
    });
  } catch (error) {
    next(error);
  }
});

app.post('/api/membership/apple/verify', async (req, res, next) => {
  try {
    const ctx = await loadUserContext(req);
    const appleConfig = getAppleIapConfig();
    const packageId = String(req.body?.package_id || '').trim();
    const expectedProductId = appleConfig.productMap.get(packageId);
    if (!expectedProductId) {
      throw Object.assign(new Error('Apple membership package is not configured.'), {
        statusCode: 400,
      });
    }
    const submittedProductId = String(req.body?.product_id || '').trim();
    if (submittedProductId !== expectedProductId) {
      throw Object.assign(new Error('Apple product does not match the selected membership package.'), {
        statusCode: 400,
      });
    }
    const transactionId = resolveAppleTransactionId({
      transactionId: req.body?.transaction_id,
      signedTransaction: req.body?.server_verification_data,
    });
    const transaction = await fetchAndValidateAppleTransaction({
      transactionId,
      signedTransaction: req.body?.server_verification_data,
      expectedProductId,
      config: appleConfig,
    });
    const memberPackage = findMemberPackage(ctx.memberInfo, Number(packageId));
    if (!memberPackage) {
      throw Object.assign(new Error('Membership package was not found.'), { statusCode: 404 });
    }
    const entitlement = await grantAppleMembership({
      ctx,
      packageId,
      memberPackage,
      transaction,
    });
    res.json({
      success: true,
      code: 200,
      status: entitlement.memberActive ? 'active' : 'expired',
      message: entitlement.memberActive
        ? 'Apple membership entitlement updated.'
        : 'Apple purchase was verified, but the membership has expired.',
      expire_at: entitlement.expireAt,
    });
  } catch (error) {
    next(error);
  }
});

app.post('/api/membership/apple/notifications', async (req, res, next) => {
  try {
    const appleConfig = getAppleIapConfig();
    const notification = parseAppleNotification(req.body, appleConfig.productMap);
    if (!notification) {
      res.json({ success: true, status: 'ignored' });
      return;
    }
    const transaction = await fetchAndValidateAppleTransaction({
      transactionId: notification.transactionId,
      expectedProductId: notification.productId,
      config: appleConfigForNotification(appleConfig, notification.environment),
      allowRevoked: true,
    });
    const context = await findAppleNotificationMembershipContext(
      transaction.originalTransactionId,
      notification.packageId,
    );
    if (!context) {
      res.json({ success: true, status: 'ignored', reason: 'subscription_not_owned' });
      return;
    }

    const entitlement = transaction.revoked
      ? await revokeAppleMembership({
        userId: context.ctx.user.id,
        originalTransactionId: transaction.originalTransactionId,
        transaction,
      })
      : await grantAppleMembership({
        ctx: context.ctx,
        packageId: notification.packageId,
        memberPackage: context.memberPackage,
        transaction,
      });
    res.json({
      success: true,
      status: transaction.revoked ? 'revoked' : 'updated',
      notification_type: notification.notificationType,
      expire_at: entitlement.expireAt,
      member_active: entitlement.memberActive,
    });
  } catch (error) {
    next(error);
  }
});

app.get('/api/member/packages', async (req, res, next) => {
  try {
    const ctx = await loadUserContext(req);
    res.json({ ok: true, member: ctx.memberInfo });
  } catch (error) {
    next(error);
  }
});

app.post('/api/member/orders', async (req, res, next) => {
  try {
    const ctx = await loadUserContext(req);
    const packageId = String(req.body?.package_id ?? '').trim();
    const payType = String(req.body?.pay_type ?? '').trim();
    const clientPlatform = String(req.body?.client_platform ?? '').trim().toLowerCase();
    if (!packageId || !payType) {
      return jsonError(res, 400, 'package_id and pay_type are required');
    }
    if (payType === '1' && clientPlatform === 'android') {
      const appOrder = await createWechatAppMemberOrder({
        ctx,
        packageId: Number(packageId),
        req,
      });
      if (appOrder) {
        res.json({ ok: true, order: appOrder });
        return;
      }
    }
    const order = normalizeMemberOrderPaymentLinks(await postApiWeb('create_web_member_order', ctx.token, {
      package_id: packageId,
      pay_type: payType,
      subsite_name: config.subsiteName,
    }));
    await pool.execute(
      `
        INSERT INTO kq_member_orders (
          user_id, order_no, package_id, package_name, package_days,
          pay_amount, pay_type, raw_order_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
          raw_order_json = VALUES(raw_order_json),
          updated_at = NOW()
      `,
      [
        ctx.user.id,
        order.order_no,
        Number(order.package_id || 0),
        String(order.package_name || ''),
        Number(order.package_days || 0),
        Number(order.pay_amount || 0),
        Number(order.pay_type || 0),
        JSON.stringify(order),
      ],
    );
    res.json({ ok: true, order });
  } catch (error) {
    next(error);
  }
});

app.get('/api/member/orders/:orderNo', async (req, res, next) => {
  try {
    const ctx = await loadUserContext(req);
    const [localOrders] = await pool.execute(
      'SELECT * FROM kq_member_orders WHERE user_id = ? AND order_no = ? LIMIT 1',
      [ctx.user.id, req.params.orderNo],
    );
    const localOrder = localOrders[0];
    const wechatCfg = getWechatPayConfig();
    if (localOrder && Number(localOrder.pay_type || 0) === 1 && wechatCfg) {
      let status = {
        order_no: req.params.orderNo,
        pay_status: Number(localOrder.pay_status || 0),
        expire_at: localOrder.expire_at,
      };
      if (status.pay_status !== 1) {
        const wechatOrder = await queryWechatAppOrderStatus(req.params.orderNo, wechatCfg);
        if (wechatOrder?.trade_state === 'SUCCESS') {
          const paidOrder = await markProjectMemberOrderPaid(req.params.orderNo, wechatOrder);
          status = {
            order_no: req.params.orderNo,
            pay_status: 1,
            expire_at: paidOrder?.expire_at || localOrder.expire_at,
          };
        }
      }
      res.json({ ok: true, status });
      return;
    }
    const alipayCfg = getAlipayPayConfig();
    if (localOrder && isProjectAlipayAppOrder(localOrder)) {
      let status = {
        order_no: req.params.orderNo,
        pay_status: Number(localOrder.pay_status || 0),
        expire_at: localOrder.expire_at,
      };
      if (status.pay_status !== 1) {
        if (!alipayCfg) {
          throw Object.assign(new Error('Alipay APP Pay is not configured'), { statusCode: 500 });
        }
        const alipayOrder = await queryAlipayAppOrderStatus(req.params.orderNo, alipayCfg);
        if (isAlipayTradePaid(alipayOrder)) {
          assertAlipayOrderMatches(localOrder, alipayOrder, alipayCfg);
          const paidOrder = await markProjectMemberOrderPaid(req.params.orderNo, alipayOrder);
          status = {
            order_no: req.params.orderNo,
            pay_status: 1,
            expire_at: paidOrder?.expire_at || localOrder.expire_at,
          };
        }
      }
      res.json({ ok: true, status });
      return;
    }
    const status = await postApiWeb('check_web_member_order_paystatus', ctx.token, {
      order_no: req.params.orderNo,
    });
    await pool.execute(
      `
        UPDATE kq_member_orders
        SET pay_status = ?, expire_at = ?, updated_at = NOW()
        WHERE user_id = ? AND order_no = ?
      `,
      [
        Number(status.pay_status || 0),
        normalizeDateTime(status.expire_at),
        ctx.user.id,
        req.params.orderNo,
      ],
    );
    res.json({ ok: true, status });
  } catch (error) {
    next(error);
  }
});

app.post(['/api/alipay/notify', '/alipay/notify'], async (req, res) => {
  try {
    await handleAlipayPayNotification(req.body);
    res.type('text').send('success');
  } catch (error) {
    console.error(error);
    res.status(error.statusCode || 400).type('text').send('fail');
  }
});

app.post(['/api/wechat-pay/notify', '/wechat-pay/notify'], async (req, res, next) => {
  try {
    await handleWechatPayNotification(req.body);
    res.status(204).end();
  } catch (error) {
    next(error);
  }
});

app.use((error, _req, res, _next) => {
  const status = error.statusCode || 500;
  if (status >= 500) {
    console.error(error);
  }
  jsonError(res, status, error.message || 'internal error');
});

await ensureDatabase();
app.listen(config.port, config.host, () => {
  console.log(`KQ Remote Link API listening on ${config.host}:${config.port}`);
});
