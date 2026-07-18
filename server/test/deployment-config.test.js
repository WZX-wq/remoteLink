import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function configuredValue(text, key) {
  const line = text
    .split(/\r?\n/)
    .find((entry) => entry.startsWith(`${key}=`));
  return line == null ? '' : line.slice(key.length + 1).trim();
}

test('production environment template contains placeholders instead of live credentials', () => {
  for (const relativePath of [
    '../../deploy/kq-production.env.example',
    '../../docs/kq-production.env.example',
  ]) {
    const templatePath = path.resolve(__dirname, relativePath);
    if (!fs.existsSync(templatePath)) continue;
    const template = fs.readFileSync(templatePath, 'utf8');
    const unsafeCredentialPresent = [
      'KQ_DB_USER',
      'KQ_DB_PASSWORD',
      'KQ_ALIPAY_PRIVATE_KEY',
      'KQ_WECHAT_PAY_PRIVATE_KEY',
    ].some((key) => configuredValue(template, key) !== '');

    assert.equal(unsafeCredentialPresent, false);
    assert.equal(template.includes('-----BEGIN PRIVATE KEY-----'), false);
  }
});

test('deployment script preserves iOS account and Apple verification environment variables', () => {
  const script = fs.readFileSync(
    path.resolve(__dirname, '../../deploy/deploy-rustdesk-server.sh'),
    'utf8',
  );
  const allVariablesPresent = [
    'KQ_ACCOUNT_DELETION_MODE',
    'KQ_IDENTITY_ACCOUNT_DELETE_URL',
    'KQ_IOS_IAP_PRODUCTS',
    'KQ_APPLE_IAP_BUNDLE_ID',
    'KQ_APPLE_IAP_ISSUER_ID',
    'KQ_APPLE_IAP_KEY_ID',
    'KQ_APPLE_IAP_PRIVATE_KEY_PATH',
    'KQ_APPLE_IAP_ENVIRONMENT',
  ].every((key) => script.includes(key));
  assert.equal(allVariablesPresent, true);
});

test('test-server workflow keeps iOS deletion in isolated local-test mode', () => {
  const workflow = fs.readFileSync(
    path.resolve(__dirname, '../../.gitea/workflows/deploy-test-ios-api.yml'),
    'utf8',
  );
  for (const value of [
    'test-server-ios-api-20260718',
    'KQ_ACCOUNT_DELETION_MODE: local_test',
    'KQ_ENABLE_LOCAL_DB: "Y"',
    'KQ_DB_PORT: "23306"',
    'http://43.154.197.96/kq-api/api',
    '/api/auth/account/delete',
    '/api/membership/apple/verify',
  ]) {
    assert.equal(workflow.includes(value), true);
  }
});
