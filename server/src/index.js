import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import mysql from 'mysql2/promise';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const defaultInstallerPath = path.resolve(
  __dirname,
  '../public/downloads/Kunqiong-Remote-Desktop-Setup.exe',
);

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
    deriveDownloadUrl(process.env.KQ_PUBLIC_API_URL) ||
    '/download/windows',
  download: {
    filePath: process.env.KQ_DOWNLOAD_FILE_PATH || defaultInstallerPath,
    fileName:
      process.env.KQ_DOWNLOAD_FILE_NAME ||
      'Kunqiong-Remote-Desktop-Setup.exe',
    version: process.env.KQ_DOWNLOAD_VERSION || '2026.06.05.1708',
    sha256: process.env.KQ_DOWNLOAD_SHA256 || '',
    maxRequestsPerWindow: envInt('KQ_DOWNLOAD_MAX_REQUESTS_PER_WINDOW', 12, 1, 120),
    windowMs: envInt('KQ_DOWNLOAD_RATE_WINDOW_MS', 60000, 1000, 3600000),
    maxPerIpConcurrent: envInt('KQ_DOWNLOAD_MAX_PER_IP_CONCURRENT', 2, 1, 16),
    maxGlobalConcurrent: envInt('KQ_DOWNLOAD_MAX_GLOBAL_CONCURRENT', 8, 1, 128),
  },
  appScheme: normalizeUriScheme(process.env.KQ_APP_SCHEME || 'kqremote'),
};

let pool;
const downloadLimiter = {
  active: 0,
  clients: new Map(),
};

function mustEnv(name) {
  const value = process.env[name];
  if (!value || !value.trim()) {
    throw new Error(`${name} is required`);
  }
  return value.trim();
}

function deriveDownloadUrl(publicApiUrl) {
  const text = String(publicApiUrl || '').trim();
  if (!text) return '';
  try {
    const url = new URL(text);
    url.pathname = url.pathname.replace(/\/api\/?$/, '').replace(/\/+$/, '');
    url.pathname = `${url.pathname}/download/windows`;
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
  const source = data?.user && typeof data.user === 'object' ? data.user : data;
  const externalUserId = String(
    source?.id ??
      source?.user_id ??
      source?.uid ??
      source?.uuid ??
      source?.username ??
      source?.name ??
      sha256(token).slice(0, 32),
  );
  const username = String(source?.username ?? source?.name ?? externalUserId);
  return {
    externalUserId,
    username,
    nickname: String(source?.nickname ?? source?.display_name ?? source?.displayName ?? username),
    email: String(source?.email ?? ''),
    avatarUrl: String(source?.avatar ?? source?.avatar_url ?? ''),
    raw: data ?? {},
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

async function loadUserContext(req) {
  const token = getAuthToken(req);
  if (!token) {
    throw Object.assign(new Error('missing token'), { statusCode: 401 });
  }
  const userInfo = await postApiWeb('user_all_info', token);
  const memberInfo = await postApiWeb('get_web_member_package_info', token, {
    subsite_name: config.subsiteName,
  });
  const user = normalizeUserPayload(userInfo, token);
  const dbUser = await upsertUser({
    ...user,
    tokenHash: sha256(token),
    memberActive: toBool(memberInfo.web_member_active),
    memberExpireAt: memberInfo.web_member_expire_at || null,
  });
  await saveMemberSnapshot(dbUser, memberInfo);
  return { token, user: dbUser, userInfo, memberInfo };
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
    textError(res, 429, 'Download rate limit exceeded. Please try again later.');
    return null;
  }
  if (state.active >= config.download.maxPerIpConcurrent) {
    textError(res, 429, 'Too many concurrent downloads from this network.');
    return null;
  }
  if (downloadLimiter.active >= config.download.maxGlobalConcurrent) {
    textError(res, 503, 'Download server is busy. Please try again later.');
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

async function sendWindowsInstaller(req, res) {
  const releaseDownload = req.method !== 'HEAD' ? acquireDownloadSlot(req, res) : () => {};
  if (!releaseDownload) return;
  try {
    const stat = await fs.promises.stat(config.download.filePath);
    if (!stat.isFile()) {
      releaseDownload();
      textError(res, 404, 'Installer file is not available.');
      return;
    }

    const range = parseRangeHeader(req.get('range'), stat.size);
    if (range?.invalid) {
      releaseDownload();
      res.setHeader('content-range', `bytes */${stat.size}`);
      textError(res, 416, 'Requested range is not satisfiable.');
      return;
    }

    const start = range ? range.start : 0;
    const end = range ? range.end : stat.size - 1;
    const contentLength = end - start + 1;
    const dispositionName = config.download.fileName.replace(/["\\]/g, '');
    const headers = {
      'accept-ranges': 'bytes',
      'cache-control': 'private, max-age=300',
      'content-type': 'application/vnd.microsoft.portable-executable',
      'content-disposition': `attachment; filename="${dispositionName}"; filename*=UTF-8''${encodeURIComponent(config.download.fileName)}`,
      'content-length': String(contentLength),
      'x-kq-download-version': config.download.version,
    };
    if (config.download.sha256) {
      headers['x-kq-download-sha256'] = config.download.sha256;
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

    const stream = fs.createReadStream(config.download.filePath, { start, end });
    const finish = () => releaseDownload();
    stream.on('error', (error) => {
      console.error(error);
      if (!res.headersSent) {
        textError(res, 500, 'Could not read installer file.');
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
      textError(res, 404, 'Installer file is not available.');
      return;
    }
    throw error;
  }
}

function htmlEscape(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
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

function invitePage(payload) {
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
  const disabledAttr = isExpired ? 'disabled aria-disabled="true"' : '';
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>鲲穹远程协助邀请</title>
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
    .mark {
      width: 44px;
      height: 44px;
      border-radius: 14px;
      display: grid;
      place-items: center;
      color: white;
      font-weight: 900;
      background: linear-gradient(135deg, #19c8f0, #126fe8 58%, #5a7cff);
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
    a.button { color: var(--ink); background: #fff; border-color: rgba(16, 36, 62, .14); }
    .status { min-height: 24px; margin-top: 18px; text-align: center; color: ${isExpired ? '#e23b2e' : '#5d7190'}; font-size: 14px; font-weight: 700; }
    @media (prefers-color-scheme: dark) {
      :root { --ink: #e8f2ff; --muted: #9bb6d3; --panel: rgba(18, 29, 43, .86); --soft: rgba(30,48,69,.86); --line: rgba(76, 137, 184, .5); }
      body { background: linear-gradient(135deg, #102033 0%, #14283d 45%, #1d274a 100%); }
      .info { background: rgba(15, 26, 40, .68); }
      a.button { background: rgba(255,255,255,.08); color: var(--ink); border-color: rgba(160, 205, 244, .2); }
    }
  </style>
</head>
<body>
  <main>
    <section class="brand">
      <div class="mark">鲲</div>
      <h1>鲲穹远程桌面</h1>
    </section>
    <p class="subtitle">邀请你进行远程协助</p>
    <section class="info">
      <div class="row"><span>设备 ID</span><strong>${safeId}</strong></div>
      <div class="row"><span>设备验证码</span><strong>${safePassword}</strong></div>
      <div class="row"><span>邀请时间</span><strong>${safeCreatedAt}</strong></div>
      <div class="row"><span>有效期</span><strong>24 小时</strong></div>
    </section>
    <section class="actions">
      <button class="primary" id="openApp" ${disabledAttr}>开始远控</button>
      <a class="button" href="download" rel="noopener">下载鲲穹远程桌面</a>
    </section>
    <div class="status" id="status">${isExpired ? '此链接已失效' : ''}</div>
  </main>
  <script>
    const deepLink = ${JSON.stringify(deepLink)};
    const expired = ${JSON.stringify(isExpired)};
    document.getElementById('openApp').addEventListener('click', () => {
      if (expired) return;
      document.getElementById('status').textContent = '正在打开鲲穹远程桌面...';
      window.location.href = deepLink;
      window.setTimeout(() => {
        document.getElementById('status').textContent = '如果没有自动打开，请确认已安装客户端，或点击下载按钮。';
      }, 1500);
    });
  </script>
</body>
</html>`;
}

function downloadPage() {
  const safeDownloadUrl = htmlEscape(config.downloadUrl);
  const safeOfficialUrl = htmlEscape('https://kunqiongai.com/');
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>下载鲲穹远程桌面</title>
  <style>
    :root {
      color-scheme: light dark;
      --ink: #10243e;
      --muted: #5d7190;
      --primary: #147cde;
      --primary-2: #0f65bf;
      --line: rgba(96, 166, 224, .36);
      --panel: rgba(255, 255, 255, .82);
      --soft: rgba(235, 247, 255, .9);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: "Microsoft YaHei", "PingFang SC", system-ui, sans-serif;
      color: var(--ink);
      background:
        linear-gradient(120deg, rgba(255,255,255,.7), rgba(255,255,255,0) 36%),
        radial-gradient(circle at 20% 16%, rgba(87, 206, 232, .42), transparent 30rem),
        radial-gradient(circle at 88% 20%, rgba(130, 169, 255, .52), transparent 28rem),
        linear-gradient(135deg, #e3f7ff 0%, #f3f9ff 44%, #e6ecff 100%);
    }
    .shell {
      width: min(1080px, calc(100vw - 36px));
      margin: 0 auto;
      padding: 30px 0 42px;
    }
    header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 18px;
      margin-bottom: 52px;
    }
    .brand { display: flex; align-items: center; gap: 12px; font-weight: 900; font-size: 19px; }
    .mark {
      width: 42px;
      height: 42px;
      border-radius: 12px;
      display: grid;
      place-items: center;
      color: white;
      background: linear-gradient(135deg, #18c6ef, #147cde 58%, #5a7cff);
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
      grid-template-columns: minmax(0, 1.05fr) minmax(320px, .95fr);
      gap: 34px;
      align-items: center;
    }
    .hero h1 {
      margin: 0 0 16px;
      font-size: clamp(34px, 5.4vw, 64px);
      line-height: 1.02;
      letter-spacing: 0;
    }
    .hero p {
      max-width: 560px;
      margin: 0;
      color: var(--muted);
      font-size: 18px;
      line-height: 1.7;
      font-weight: 700;
    }
    .panel {
      border: 1px solid rgba(255,255,255,.72);
      border-radius: 16px;
      padding: 26px;
      background: var(--panel);
      box-shadow: 0 30px 84px rgba(15, 42, 72, .18);
      backdrop-filter: blur(18px);
    }
    .panel h2 { margin: 0 0 8px; font-size: 24px; letter-spacing: 0; }
    .panel .desc { margin: 0 0 22px; color: var(--muted); line-height: 1.55; font-weight: 700; }
    .download {
      width: 100%;
      height: 48px;
      border: 0;
      border-radius: 10px;
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
    .meta {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 10px;
      margin-top: 18px;
    }
    .meta div {
      min-height: 72px;
      padding: 12px;
      border-radius: 10px;
      border: 1px solid var(--line);
      background: rgba(255,255,255,.56);
    }
    .meta strong { display: block; margin-bottom: 6px; font-size: 18px; }
    .meta span { color: var(--muted); font-size: 13px; font-weight: 700; }
    @media (prefers-color-scheme: dark) {
      :root { --ink: #e8f2ff; --muted: #9bb6d3; --panel: rgba(18, 29, 43, .86); --soft: rgba(30,48,69,.86); --line: rgba(76, 137, 184, .48); }
      body { background: linear-gradient(135deg, #102033 0%, #14283d 45%, #1d274a 100%); }
      .official, .meta div { background: rgba(255,255,255,.08); }
    }
    @media (max-width: 760px) {
      header { margin-bottom: 34px; }
      main { grid-template-columns: 1fr; }
      .hero h1 { font-size: 40px; }
      .meta { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <div class="shell">
    <header>
      <div class="brand"><div class="mark">鲲</div><span>鲲穹远程桌面</span></div>
      <a class="official" href="${safeOfficialUrl}" rel="noopener">公司官网</a>
    </header>
    <main>
      <section class="hero">
        <h1>安全、清爽、好用的远程协助工具</h1>
        <p>用于远程桌面、临时协助、跨设备办公和售后支持。安装后可直接打开分享链接，一键进入连接流程。</p>
      </section>
      <section class="panel">
        <h2>Windows 客户端</h2>
        <p class="desc">下载安装并完成向导后，再次点击邀请链接里的“开始远控”即可自动唤起客户端。测试环境下载入口已启用限流保护。</p>
        <a class="download" href="${safeDownloadUrl}" rel="noopener">下载 Windows 安装包</a>
        <div class="meta">
          <div><strong>v${htmlEscape(config.download.version)}</strong><span>当前 Windows 安装包</span></div>
          <div><strong>断点续传</strong><span>网络波动可继续下载</span></div>
          <div><strong>受控下载</strong><span>避免测试服务器被打满</span></div>
        </div>
      </section>
    </main>
  </div>
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

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: false }));
app.use((req, res, next) => {
  res.setHeader('access-control-allow-origin', '*');
  res.setHeader('access-control-allow-methods', 'GET,POST,OPTIONS');
  res.setHeader(
    'access-control-allow-headers',
    'authorization,content-type,token,x-kq-token',
  );
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }
  next();
});

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
    .send(invitePage(decodeInvitePayload(req)));
});

app.get(['/download', '/api/download'], (_req, res) => {
  res
    .status(200)
    .type('html')
    .send(downloadPage());
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

app.get('/api/connection-history', async (req, res, next) => {
  try {
    const ctx = await loadUserContext(req);
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
    const ctx = await loadUserContext(req);
    const peer = normalizePeer(req.body);
    await savePeerHistory(ctx.user, peer);
    const limit = connectionLimitFor(ctx.user);
    res.json({ ok: true, limit });
  } catch (error) {
    next(error);
  }
});

app.post('/api/connection-history/bulk', async (req, res, next) => {
  try {
    const ctx = await loadUserContext(req);
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
    if (!packageId || !payType) {
      return jsonError(res, 400, 'package_id and pay_type are required');
    }
    const order = await postApiWeb('create_web_member_order', ctx.token, {
      package_id: packageId,
      pay_type: payType,
      subsite_name: config.subsiteName,
    });
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
