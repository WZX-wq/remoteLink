import fs from 'node:fs';
import { parseAppleProductMap } from './apple-iap.js';

function privateKeyPathReadable(filePath, fsImpl) {
  const normalized = String(filePath || '').trim();
  if (!normalized) return false;
  try {
    fsImpl.accessSync(normalized, fsImpl.constants.R_OK);
    return true;
  } catch (_) {
    return false;
  }
}

export function appleIapReadiness(appleIap, fsImpl = fs) {
  let productsConfigured = false;
  try {
    productsConfigured = parseAppleProductMap(appleIap?.productsJson).size > 0;
  } catch (_) {
    // The readiness response deliberately contains status only, never values.
  }
  const privateKeySource = appleIap?.privateKeySource ||
    (appleIap?.privateKey ? 'inline' : appleIap?.privateKeyPath ? 'path' : 'missing');
  const environment = String(appleIap?.environment || '').trim().toLowerCase();
  const validEnvironment = environment === 'sandbox' || environment === 'production';
  const privateKeyConfigured = Boolean(String(appleIap?.privateKey || '').trim());
  const pathReadable = privateKeySource === 'path'
    ? privateKeyPathReadable(appleIap?.privateKeyPath, fsImpl)
    : null;
  const bundleIdConfigured = Boolean(String(appleIap?.bundleId || '').trim());
  const issuerIdConfigured = Boolean(String(appleIap?.issuerId || '').trim());
  const keyIdConfigured = Boolean(String(appleIap?.keyId || '').trim());
  return {
    products_configured: productsConfigured,
    bundle_id_configured: bundleIdConfigured,
    issuer_id_configured: issuerIdConfigured,
    key_id_configured: keyIdConfigured,
    private_key_configured: privateKeyConfigured,
    private_key_source: privateKeySource,
    private_key_path_readable: pathReadable,
    environment: validEnvironment ? environment : 'invalid',
    ready:
      productsConfigured &&
      bundleIdConfigured &&
      issuerIdConfigured &&
      keyIdConfigured &&
      privateKeyConfigured &&
      validEnvironment,
  };
}
