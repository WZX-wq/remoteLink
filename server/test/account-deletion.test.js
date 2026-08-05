import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  AccountDeletionError,
  accountDeletionIdentity,
  accountDeletionBlocksLogin,
  normalizeAccountDeletionMode,
  submitAccountDeletion,
} from '../src/account-deletion.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

test('treats disabled or missing deletion mode as project account deletion', () => {
  assert.equal(normalizeAccountDeletionMode(), 'local_project');
  assert.equal(normalizeAccountDeletionMode('disabled'), 'local_project');
});

test('project account deletion blocks future automatic login rebuilds', () => {
  assert.equal(accountDeletionBlocksLogin('local_project'), true);
  assert.equal(accountDeletionBlocksLogin('disabled'), true);
  assert.equal(accountDeletionBlocksLogin('upstream'), true);
  assert.equal(accountDeletionBlocksLogin('local_test'), false);
});

test('deletion lookup accepts normalized and persisted user identities', () => {
  assert.deepEqual(
    accountDeletionIdentity({
      externalUserId: 'upstream-user-1',
    }),
    {
      externalProvider: 'kunqiong',
      externalUserId: 'upstream-user-1',
    },
  );
  assert.deepEqual(
    accountDeletionIdentity({
      external_provider: 'kunqiong',
      external_user_id: 'database-user-1',
    }),
    {
      externalProvider: 'kunqiong',
      externalUserId: 'database-user-1',
    },
  );
  assert.equal(accountDeletionIdentity({}), null);
});

test('identity login checks deletion tombstone before recreating a local user', () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, '../src/index.js'),
    'utf8',
  );
  const start = source.indexOf('async function loadUserIdentityContextForToken');
  const end = source.indexOf('async function loadUserContext', start);
  assert.notEqual(start, -1);
  assert.ok(end > start);
  const body = source.slice(start, end);
  const check = body.indexOf('assertAccountDeletionDoesNotBlock(user)');
  const upsert = body.indexOf('upsertUserIdentity');
  assert.notEqual(check, -1);
  assert.notEqual(upsert, -1);
  assert.ok(check < upsert, 'deletion tombstone check must run before upsertUserIdentity');
  assert.equal(source.includes('This account has a pending deletion request.'), false);
  assert.equal(source.includes('账号已注销，请重新注册后再登录。'), true);
});

test('database startup removes users recreated after account deletion', () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, '../src/index.js'),
    'utf8',
  );
  const cleanupStart = source.indexOf('async function cleanupDeletedAccountRebuilds');
  const ensureStart = source.indexOf('async function ensureDatabase');
  const listenStart = source.indexOf('app.listen', ensureStart);
  assert.notEqual(cleanupStart, -1);
  assert.notEqual(ensureStart, -1);
  assert.ok(listenStart > ensureStart);

  const cleanupBody = source.slice(cleanupStart, ensureStart);
  assert.equal(cleanupBody.includes('kq_account_deletion_requests'), true);
  assert.equal(cleanupBody.includes('LEFT JOIN kq_users AS owner_user'), true);
  assert.equal(cleanupBody.includes('WHERE owner_user.id IS NULL'), true);
  assert.equal(cleanupBody.includes("deletion.status IN ('pending', 'processing', 'deleted')"), true);
  assert.equal(cleanupBody.includes("deletion.request_scope IN ('project_account', 'identity_service')"), true);
  assert.equal(cleanupBody.includes('DELETE subscription_owner'), true);
  assert.equal(cleanupBody.includes('DELETE deleted_user'), true);

  const ensureBody = source.slice(ensureStart, listenStart);
  const ownerTable = ensureBody.indexOf('CREATE TABLE IF NOT EXISTS kq_apple_subscription_owners');
  const cleanupCall = ensureBody.indexOf('await cleanupDeletedAccountRebuilds()');
  assert.notEqual(ownerTable, -1);
  assert.notEqual(cleanupCall, -1);
  assert.ok(ownerTable < cleanupCall, 'cleanup must run after related tables exist');
});

test('local project deletion releases Apple ownership and transactions before user rows', () => {
  const source = fs.readFileSync(
    path.resolve(__dirname, '../src/index.js'),
    'utf8',
  );
  const start = source.indexOf('async function deleteLocalProjectAccount');
  const end = source.indexOf('async function cleanupDeletedAccountRebuilds', start);
  assert.notEqual(start, -1);
  assert.ok(end > start);
  const body = source.slice(start, end);
  const ownerDelete = body.indexOf('DELETE FROM kq_apple_subscription_owners WHERE user_id = ?');
  const transactionDelete = body.indexOf('DELETE FROM kq_apple_transactions WHERE user_id = ?');
  const userDelete = body.indexOf('DELETE FROM kq_users WHERE id = ?');
  assert.notEqual(ownerDelete, -1);
  assert.notEqual(transactionDelete, -1);
  assert.notEqual(userDelete, -1);
  assert.ok(ownerDelete < userDelete, 'subscription owners have no FK cascade and must be removed first');
  assert.ok(transactionDelete < userDelete, 'Apple transactions must be released before deleting the account');
});

test('defaults to project account deletion instead of failing when upstream is absent', async () => {
  const result = await submitAccountDeletion({
    token: 'test-token',
    confirmation: 'DELETE',
  });

  assert.deepEqual(result, {
    status: 'deleted',
    statusCode: 200,
    message: 'Account deleted.',
    localOnly: false,
    requestScope: 'project_account',
  });
});

test('keeps test-only deletion in pending state instead of claiming the identity account was deleted', async () => {
  const result = await submitAccountDeletion({
    mode: 'local_test',
    token: 'test-token',
    confirmation: 'DELETE',
  });

  assert.deepEqual(result, {
    status: 'pending',
    statusCode: 202,
    message: 'Test environment deletion request accepted.',
    localOnly: true,
    requestScope: 'local_test',
  });
});

test('upstream account deletion requires a configured HTTPS URL', async () => {
  await assert.rejects(
    () =>
      submitAccountDeletion({
        mode: 'upstream',
        upstreamUrl: '',
        token: 'member-token',
        confirmation: 'DELETE',
      }),
    (error) =>
      error instanceof AccountDeletionError &&
      error.statusCode === 503 &&
      error.message === 'Account deletion service must use HTTPS.',
  );
});

test('forwards a production deletion request with the caller bearer token', async () => {
  let request;
  const result = await submitAccountDeletion({
    mode: 'upstream',
    upstreamUrl: 'https://identity.example.com/api/auth/account/delete',
    token: 'member-token',
    confirmation: 'DELETE',
    fetchImpl: async (url, options) => {
      request = { url: String(url), options };
      return new Response(
        JSON.stringify({
          success: true,
          status: 'pending',
          message: 'Deletion request received.',
        }),
        { status: 202, headers: { 'content-type': 'application/json' } },
      );
    },
  });

  assert.equal(request.url, 'https://identity.example.com/api/auth/account/delete');
  assert.equal(request.options.headers.Authorization, 'Bearer member-token');
  assert.deepEqual(JSON.parse(request.options.body), { confirmation: 'DELETE' });
  assert.equal(result.status, 'pending');
  assert.equal(result.localOnly, false);
});

test('accepts the upstream DELETE confirmation response contract', async () => {
  let request;
  const result = await submitAccountDeletion({
    mode: 'upstream',
    upstreamUrl: 'https://identity.example.com/api/auth/account/delete',
    token: 'current-login-token',
    confirmation: 'DELETE',
    fetchImpl: async (url, options) => {
      request = { url: String(url), options };
      return new Response(
        JSON.stringify({
          success: true,
          status: 'deleted',
          message: '账号已注销',
        }),
        { status: 200, headers: { 'content-type': 'application/json' } },
      );
    },
  });

  assert.equal(request.url, 'https://identity.example.com/api/auth/account/delete');
  assert.equal(request.options.method, 'POST');
  assert.equal(request.options.headers.Authorization, 'Bearer current-login-token');
  assert.equal(request.options.headers['Content-Type'], 'application/json');
  assert.equal(request.options.headers.Accept, 'application/json');
  assert.deepEqual(JSON.parse(request.options.body), { confirmation: 'DELETE' });
  assert.deepEqual(result, {
    status: 'deleted',
    statusCode: 200,
    message: '账号已注销',
    localOnly: false,
    requestScope: 'identity_service',
  });
});

test('rejects a deletion request when the identity service does not accept it', async () => {
  await assert.rejects(
    () =>
      submitAccountDeletion({
        mode: normalizeAccountDeletionMode('upstream'),
        upstreamUrl: 'https://identity.example.com/api/auth/account/delete',
        token: 'member-token',
        confirmation: 'DELETE',
        fetchImpl: async () =>
          new Response(
            JSON.stringify({ success: false, message: 'Please verify your phone first.' }),
            { status: 409, headers: { 'content-type': 'application/json' } },
          ),
      }),
    (error) =>
      error instanceof AccountDeletionError &&
      error.statusCode === 409 &&
      error.message === 'Please verify your phone first.',
  );
});
