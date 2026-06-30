import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createRequestGate } from '../src/request-gate.js';

function tempStateFile() {
  return path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'kq-request-gate-')), 'gate.json');
}

function req({
  method = 'GET',
  url = '/api/me',
  body = {},
  headers = {},
  query = {},
} = {}) {
  return {
    method,
    url,
    path: url,
    body,
    query,
    get(name) {
      return headers[name.toLowerCase()] || '';
    },
  };
}

function res() {
  return {
    statusCode: 200,
    headers: {},
    payload: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    setHeader(name, value) {
      this.headers[name.toLowerCase()] = value;
    },
    json(value) {
      this.payload = value;
      return this;
    },
  };
}

test('request gate defaults to accepting requests', () => {
  const gate = createRequestGate({
    stateFile: tempStateFile(),
    adminToken: 'secret',
  });

  assert.deepEqual(gate.readState(), {
    accepting_requests: true,
    message: '服务正常',
    updated_at: null,
  });
});

test('request gate persists maintenance state', () => {
  const stateFile = tempStateFile();
  const gate = createRequestGate({
    stateFile,
    adminToken: 'secret',
    now: () => new Date('2026-06-29T08:00:00.000Z'),
  });

  gate.writeState({
    accepting_requests: false,
    message: '升级维护中',
  });

  const reloaded = createRequestGate({ stateFile, adminToken: 'secret' });
  assert.deepEqual(reloaded.readState(), {
    accepting_requests: false,
    message: '升级维护中',
    updated_at: '2026-06-29T08:00:00.000Z',
  });
});

test('request gate rejects invalid admin token', () => {
  const gate = createRequestGate({
    stateFile: tempStateFile(),
    adminToken: 'secret',
  });
  const response = res();
  let called = false;

  gate.requireAdmin(
    req({ headers: { 'x-kq-admin-token': 'wrong' } }),
    response,
    () => {
      called = true;
    },
  );

  assert.equal(called, false);
  assert.equal(response.statusCode, 401);
  assert.equal(response.payload.error, 'unauthorized');
});

test('request gate allows health route while closed', () => {
  const gate = createRequestGate({
    stateFile: tempStateFile(),
    adminToken: 'secret',
  });
  gate.writeState({ accepting_requests: false, message: '维护中' });

  const response = res();
  let called = false;
  gate.middleware(req({ url: '/api/health' }), response, () => {
    called = true;
  });

  assert.equal(called, true);
  assert.equal(response.payload, undefined);
});

test('request gate blocks business routes while closed', () => {
  const gate = createRequestGate({
    stateFile: tempStateFile(),
    adminToken: 'secret',
  });
  gate.writeState({ accepting_requests: false, message: '维护中' });

  const response = res();
  let called = false;
  gate.middleware(req({ url: '/api/account-devices' }), response, () => {
    called = true;
  });

  assert.equal(called, false);
  assert.equal(response.statusCode, 503);
  assert.equal(response.headers['retry-after'], '60');
  assert.equal(response.payload.error, '维护中');
  assert.equal(response.payload.gate.accepting_requests, false);
});

test('request gate updates state through admin handler', () => {
  const gate = createRequestGate({
    stateFile: tempStateFile(),
    adminToken: 'secret',
    now: () => new Date('2026-06-29T08:00:00.000Z'),
  });
  const response = res();

  gate.handlePost(
    req({
      method: 'POST',
      url: '/api/admin/request-gate',
      body: { accepting_requests: false, message: '暂停接入' },
    }),
    response,
  );

  assert.equal(response.statusCode, 200);
  assert.equal(response.payload.ok, true);
  assert.equal(response.payload.gate.accepting_requests, false);
  assert.equal(gate.readState().message, '暂停接入');
});
