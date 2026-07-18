export class AccountDeletionError extends Error {
  constructor(message, statusCode = 400) {
    super(message);
    this.name = 'AccountDeletionError';
    this.statusCode = statusCode;
  }
}

export function normalizeAccountDeletionMode(value) {
  const mode = String(value || 'disabled').trim().toLowerCase();
  if (mode === 'local_test' || mode === 'upstream' || mode === 'disabled') {
    return mode;
  }
  return 'disabled';
}

function readMessage(body, fallback) {
  if (!body || typeof body !== 'object') return fallback;
  for (const key of ['message', 'msg', 'error']) {
    const value = String(body[key] || '').trim();
    if (value) return value;
  }
  return fallback;
}

function validateRequest(token, confirmation) {
  if (!String(token || '').trim()) {
    throw new AccountDeletionError('Please log in before deleting your account.', 401);
  }
  if (String(confirmation || '').trim() !== 'DELETE') {
    throw new AccountDeletionError('Enter DELETE to confirm account deletion.');
  }
}

export async function submitAccountDeletion({
  mode,
  upstreamUrl,
  token,
  confirmation,
  fetchImpl = fetch,
}) {
  validateRequest(token, confirmation);
  const normalizedMode = normalizeAccountDeletionMode(mode);
  if (normalizedMode === 'local_test') {
    return {
      status: 'pending',
      statusCode: 202,
      message: 'Test environment deletion request accepted.',
      localOnly: true,
    };
  }
  if (normalizedMode !== 'upstream') {
    throw new AccountDeletionError('Account deletion is not configured on the server.', 503);
  }
  const target = new URL(String(upstreamUrl || '').trim());
  if (target.protocol !== 'https:') {
    throw new AccountDeletionError('Account deletion service must use HTTPS.', 503);
  }

  let response;
  try {
    response = await fetchImpl(target, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        Authorization: `Bearer ${String(token).trim()}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ confirmation: 'DELETE' }),
    });
  } catch (_) {
    throw new AccountDeletionError('Unable to submit the deletion request. Please try again later.', 502);
  }

  let body = null;
  try {
    body = await response.json();
  } catch (_) {
    // The upstream status and a safe fallback still provide a useful response.
  }
  const fallback = response.ok
    ? 'Deletion request received.'
    : 'The deletion request could not be completed.';
  const message = readMessage(body, fallback);
  if (!response.ok || body?.success === false) {
    const statusCode = response.status >= 400 && response.status < 500 ? response.status : 502;
    throw new AccountDeletionError(message, statusCode);
  }
  const status = String(body?.status || (response.status === 202 ? 'pending' : 'deleted'))
    .trim()
    .toLowerCase();
  if (status !== 'pending' && status !== 'processing' && status !== 'deleted') {
    throw new AccountDeletionError('The account service returned an invalid deletion status.', 502);
  }
  return {
    status: status === 'processing' ? 'pending' : status,
    statusCode: response.status === 202 || status !== 'deleted' ? 202 : 200,
    message,
    localOnly: false,
  };
}
