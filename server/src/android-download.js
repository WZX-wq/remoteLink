import crypto from 'node:crypto';
import fs from 'node:fs';

function sha256File(filePath) {
  return crypto
    .createHash('sha256')
    .update(fs.readFileSync(filePath))
    .digest('hex')
    .toUpperCase();
}

function readMetadata(metadataPath) {
  try {
    const parsed = JSON.parse(fs.readFileSync(metadataPath, 'utf8'));
    if (!parsed || typeof parsed !== 'object') return null;
    const version = String(parsed.version || '').trim();
    const sha256 = String(parsed.sha256 || '').trim().toUpperCase();
    if (!version || !/^[A-F0-9]{64}$/.test(sha256)) return null;
    return { version, sha256 };
  } catch {
    return null;
  }
}

export function resolveAndroidDownloadMetadata({
  apkPath,
  metadataPath = `${apkPath}.json`,
  fallbackVersion,
}) {
  const sha256 = sha256File(apkPath);
  const metadata = readMetadata(metadataPath);

  return {
    version:
      metadata?.sha256 === sha256
        ? metadata.version
        : String(fallbackVersion || '').trim(),
    sha256,
  };
}
