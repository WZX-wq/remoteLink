import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { resolveAndroidDownloadMetadata } from '../src/android-download.js';

function sha256(filePath) {
  return crypto
    .createHash('sha256')
    .update(fs.readFileSync(filePath))
    .digest('hex')
    .toUpperCase();
}

function withFixture(callback) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'kq-android-download-'));
  try {
    callback(directory);
  } finally {
    fs.rmSync(directory, { force: true, recursive: true });
  }
}

test('uses atomic Android sidecar version with the current APK checksum', () => {
  withFixture((directory) => {
    const apkPath = path.join(directory, 'Kunqiong-Remote-Desktop.apk');
    const metadataPath = `${apkPath}.json`;
    fs.writeFileSync(apkPath, 'current APK');
    fs.writeFileSync(
      metadataPath,
      JSON.stringify({ version: '1.4.6+4068', sha256: sha256(apkPath) }),
    );

    assert.deepEqual(
      resolveAndroidDownloadMetadata({
        apkPath,
        metadataPath,
        fallbackVersion: '1.4.6+4067',
      }),
      { version: '1.4.6+4068', sha256: sha256(apkPath) },
    );
  });
});

test('falls back when Android sidecar checksum is stale', () => {
  withFixture((directory) => {
    const apkPath = path.join(directory, 'Kunqiong-Remote-Desktop.apk');
    const metadataPath = `${apkPath}.json`;
    fs.writeFileSync(apkPath, 'old APK');
    fs.writeFileSync(
      metadataPath,
      JSON.stringify({ version: '1.4.6+4068', sha256: sha256(apkPath) }),
    );
    fs.writeFileSync(apkPath, 'new APK');

    assert.deepEqual(
      resolveAndroidDownloadMetadata({
        apkPath,
        metadataPath,
        fallbackVersion: '1.4.6+4067',
      }),
      { version: '1.4.6+4067', sha256: sha256(apkPath) },
    );
  });
});

test('uses the current APK checksum when Android sidecar is missing', () => {
  withFixture((directory) => {
    const apkPath = path.join(directory, 'Kunqiong-Remote-Desktop.apk');
    fs.writeFileSync(apkPath, 'APK without metadata');

    assert.deepEqual(
      resolveAndroidDownloadMetadata({
        apkPath,
        fallbackVersion: '1.4.6+4067',
      }),
      { version: '1.4.6+4067', sha256: sha256(apkPath) },
    );
  });
});
