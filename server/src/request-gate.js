import fs from 'node:fs';
import path from 'node:path';

const defaultMessage = '服务维护中，请稍后再试';

function normalizeState(value = {}) {
  return {
    accepting_requests: value.accepting_requests !== false,
    message: String(value.message || defaultMessage).slice(0, 200),
    updated_at: value.updated_at || null,
  };
}

function adminTokenFromRequest(req) {
  const headerToken = req.get?.('x-kq-admin-token') || req.get?.('x-admin-token') || '';
  const authorization = req.get?.('authorization') || '';
  const bearer = authorization.replace(/^Bearer\s+/i, '').trim();
  const bodyToken = req.body?.admin_token || req.query?.admin_token || '';
  return String(headerToken || bearer || bodyToken).trim();
}

function routePath(req) {
  return String(req.path || req.url || '').split('?')[0].replace(/\/+$/, '') || '/';
}

function isAllowedWhenClosed(req) {
  if (req.method === 'OPTIONS') return true;
  const pathName = routePath(req);
  if (
    pathName === '/health' ||
    pathName === '/api/health' ||
    pathName === '/invite' ||
    pathName === '/api/invite' ||
    pathName === '/download' ||
    pathName === '/api/download' ||
    pathName === '/download/windows' ||
    pathName === '/api/download/windows' ||
    pathName === '/download/android' ||
    pathName === '/api/download/android' ||
    pathName === '/admin/request-gate' ||
    pathName === '/api/admin/request-gate' ||
    pathName === '/alipay/notify' ||
    pathName === '/api/alipay/notify' ||
    pathName === '/wechat-pay/notify' ||
    pathName === '/api/wechat-pay/notify'
  ) {
    return true;
  }
  return (
    pathName.startsWith('/assets/') ||
    pathName.startsWith('/api/assets/') ||
    pathName.startsWith('/kq-api/assets/')
  );
}

export function createRequestGate({ stateFile, adminToken, now = () => new Date() }) {
  const token = String(adminToken || '').trim();
  const filePath = path.resolve(stateFile);

  function readState() {
    try {
      const text = fs.readFileSync(filePath, 'utf8');
      return normalizeState(JSON.parse(text));
    } catch (error) {
      if (error.code !== 'ENOENT') {
        console.error(`Failed to read request gate state: ${error.message}`);
      }
      return normalizeState({ accepting_requests: true, message: '服务正常' });
    }
  }

  function writeState(nextState) {
    const state = normalizeState({
      accepting_requests: nextState.accepting_requests,
      message: nextState.message,
      updated_at: now().toISOString(),
    });
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, `${JSON.stringify(state, null, 2)}\n`, 'utf8');
    return state;
  }

  function requireAdmin(req, res, next) {
    if (!token) {
      res.status(503).json({
        ok: false,
        error: 'request gate admin token is not configured',
      });
      return;
    }
    if (adminTokenFromRequest(req) !== token) {
      res.status(401).json({ ok: false, error: 'unauthorized' });
      return;
    }
    next();
  }

  function handleGet(_req, res) {
    res.json({ ok: true, gate: readState() });
  }

  function handlePost(req, res) {
    const rawAccepting = req.body?.accepting_requests ?? req.body?.acceptingRequests;
    if (typeof rawAccepting !== 'boolean') {
      res.status(400).json({
        ok: false,
        error: 'accepting_requests must be boolean',
      });
      return;
    }
    const state = writeState({
      accepting_requests: rawAccepting,
      message: req.body?.message || defaultMessage,
    });
    res.json({ ok: true, gate: state });
  }

  function middleware(req, res, next) {
    if (isAllowedWhenClosed(req)) {
      next();
      return;
    }
    const state = readState();
    if (state.accepting_requests) {
      next();
      return;
    }
    res.setHeader('Retry-After', '60');
    res.status(503).json({
      ok: false,
      error: state.message || defaultMessage,
      gate: state,
    });
  }

  return {
    filePath,
    readState,
    writeState,
    requireAdmin,
    handleGet,
    handlePost,
    middleware,
    isAllowedWhenClosed,
  };
}
