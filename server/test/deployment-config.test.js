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

function normalizeLineEndings(text) {
  return text.replace(/\r\n/g, '\n');
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

test('iOS release deployment blocks raw-IP, HTTP, and incomplete StoreKit configuration', () => {
  const script = fs.readFileSync(
    path.resolve(__dirname, '../../deploy/deploy-rustdesk-server.sh'),
    'utf8',
  );
  for (const value of [
    'KQ_IOS_RELEASE_MODE',
    'validate_ios_release_server_config()',
    'PUBLIC_HOST must be a DNS hostname, not a raw IP address',
    'KQ_ACCOUNT_DELETION_MODE must be upstream',
    'KQ_APPLE_IAP_ENVIRONMENT must be production',
    'KQ_APPLE_IAP_PRIVATE_KEY_PATH must be an existing /app/data/ path',
    'verify_ios_release_public_api()',
    '--resolve "${PUBLIC_HOST}:443:127.0.0.1"',
  ]) {
    assert.equal(script.includes(value), true);
  }
});

test('Windows publisher replaces one canonical installer and updates API metadata', () => {
  const script = fs.readFileSync(
    path.resolve(__dirname, '../../scripts/deploy/deploy-windows.sh'),
    'utf8',
  );
  for (const value of [
    'CANONICAL_FILE_NAME="${KQ_DOWNLOAD_FILE_NAME:-Kunqiong-Remote-Desktop-Setup.exe}"',
    'install -m 0644 "${installer_path}" "${API_DOWNLOAD_DIR}/${CANONICAL_FILE_NAME}"',
    'KQ_DOWNLOAD_VERSION',
    'KQ_DOWNLOAD_SHA256',
    'docker restart kq-remote-link-api',
  ]) {
    assert.equal(script.includes(value), true);
  }
  assert.equal(script.includes('cp "${installer_path}" "${API_DOWNLOAD_DIR}/$(basename'), false);
});

test('manual Windows publishing workflow verifies a download before replacing the canonical file', () => {
  const workflow = fs.readFileSync(
    path.resolve(__dirname, '../../.gitea/workflows/publish-windows-package.yml'),
    'utf8',
  );
  for (const value of [
    'workflow_dispatch:',
    'installer_url:',
    'EXPECTED_SHA256',
    'bash scripts/deploy/deploy-windows.sh',
    '--range 0-0',
    'http://43.154.197.96/kq-api/download/windows',
  ]) {
    assert.equal(workflow.includes(value), true);
  }
});

test('public privacy policy route is available for App Store metadata', () => {
  const server = fs.readFileSync(
    path.resolve(__dirname, '../src/index.js'),
    'utf8',
  );
  for (const value of [
    'function privacyPolicyPage()',
    "app.get(['/privacy', '/api/privacy']",
    '鲲穹远程桌面隐私政策',
    'Data we collect',
    'Membership and payments',
  ]) {
    assert.equal(server.includes(value), true);
  }
});

test('production workflow forwards iOS release settings and only verifies enabled releases', () => {
  const workflow = fs.readFileSync(
    path.resolve(__dirname, '../../.gitea/workflows/deploy.yml'),
    'utf8',
  );
  for (const value of [
    'KQ_IOS_RELEASE_MODE: ${{ secrets.KQ_IOS_RELEASE_MODE }}',
    'KQ_IDENTITY_ACCOUNT_DELETE_URL: ${{ secrets.KQ_IDENTITY_ACCOUNT_DELETE_URL }}',
    'KQ_IOS_IAP_PRODUCTS: ${{ secrets.KQ_IOS_IAP_PRODUCTS }}',
    'KQ_APPLE_IAP_PRIVATE_KEY_PATH: ${{ secrets.KQ_APPLE_IAP_PRIVATE_KEY_PATH }}',
    'Verify iOS release endpoints when enabled',
    'bash scripts/deploy/verify-ios-release-server.sh',
  ]) {
    assert.equal(workflow.includes(value), true);
  }
});

test('deployment script restores workflow overrides after loading an existing server env', () => {
  const script = normalizeLineEndings(
    fs.readFileSync(
      path.resolve(__dirname, '../../deploy/deploy-rustdesk-server.sh'),
      'utf8',
    ),
  );
  for (const value of [
    'capture_runtime_overrides()',
    'restore_runtime_overrides()',
    'KQ_DOWNLOAD_URL KQ_DOWNLOAD_FILE_PATH KQ_DOWNLOAD_FILE_NAME KQ_DOWNLOAD_VERSION',
    'KQ_ACCOUNT_DELETION_MODE KQ_IDENTITY_ACCOUNT_DELETE_URL KQ_IOS_IAP_PRODUCTS',
    'load_compose_env_file\n      restore_runtime_overrides',
    'load_compose_env_file\n  restore_runtime_overrides',
  ]) {
    assert.equal(script.includes(value), true);
  }
});

test('compose deployment disables legacy systemd services before starting the test stack', () => {
  const script = normalizeLineEndings(
    fs.readFileSync(
      path.resolve(__dirname, '../../deploy/deploy-rustdesk-server.sh'),
      'utf8',
    ),
  );
  for (const value of [
    'prepare_compose_runtime()',
    'kq-remote-link-watchdog.timer',
    'kq-remote-link-api.service',
    'kq-remote-link-hbbs.service',
    'prepare_compose_runtime\n  COMPOSE_PROFILES="api,local-db" compose',
  ]) {
    assert.equal(script.includes(value), true);
  }
});
test('test-server workflow keeps iOS deletion in isolated local-test mode', () => {
  const workflow = normalizeLineEndings(
    fs.readFileSync(
      path.resolve(__dirname, '../../.gitea/workflows/deploy-test-ios-api.yml'),
      'utf8',
    ),
  );
  for (const value of [
    'test-server-ios-api-20260718',
    'runs-on: linux',
    'Use the host deployment runner labeled linux for this workflow.',
    'wait_for_status()',
    'local deadline=$((SECONDS + 90))',
    'wait_for_status http://127.0.0.1:21120/api/health 200',
    'KQ_ACCOUNT_DELETION_MODE: local_test',
    'KQ_ENABLE_LOCAL_DB: "Y"',
    'KQ_DB_PORT: "23306"',
    'http://43.154.197.96/kq-api/api',
    'http://127.0.0.1:21120/privacy',
    '/api/auth/account/delete',
    '/api/membership/apple/verify',
  ]) {
    assert.equal(workflow.includes(value), true);
  }
});
