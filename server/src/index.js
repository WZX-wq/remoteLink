import crypto from 'node:crypto';
import express from 'express';
import mysql from 'mysql2/promise';

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
};

let pool;

function mustEnv(name) {
  const value = process.env[name];
  if (!value || !value.trim()) {
    throw new Error(`${name} is required`);
  }
  return value.trim();
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
