import assert from 'node:assert/strict';
import test from 'node:test';
import {
  AccountDeletionError,
  normalizeAccountDeletionMode,
  submitAccountDeletion,
} from '../src/account-deletion.js';

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
  });
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
