// One-time retirement after a verified phone migration. Explicit --apply is
// required. Archives and phone verification are checked before any mutation.
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');

const projectId = 'booklibrary-kargalar-2026';
const bucketName = `${projectId}.firebasestorage.app`;
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const parse = bytes => JSON.parse(bytes.toString().replace(/^\uFEFF/, ''));

async function main() {
  const root = process.argv[2];
  if (!root || !path.isAbsolute(root) || !process.argv.includes('--apply')) throw new Error('Usage: node retire_local_migration_backend.js <absolute-backup-directory> --apply');
  const savedBytes = await fs.readFile(path.join(root, 'cloud_backup.json'));
  if (digest(savedBytes) !== (await fs.readFile(path.join(root, 'cloud_backup.sha256'), 'utf8')).trim()) throw new Error('Cloud archive checksum failed.');
  const saved = parse(savedBytes);
  const phone = parse(await fs.readFile(path.join(root, 'phone_verification.json')));
  const migration = parse(await fs.readFile(path.join(root, 'staging', 'local_migration_input.json')));
  if (saved.projectId !== projectId || !phone.offlineStartup || phone.documentComparison !== 'exact' || phone.sqliteIntegrityCheck !== 'ok' || phone.importedDocuments !== Object.keys(migration.documents).length || phone.importedFiles !== migration.files.length) throw new Error('Phone migration verification is incomplete.');
  if (digest(await fs.readFile(path.join(root, 'local-release.apk'))) !== phone.apkSha256) throw new Error('Verified APK checksum failed.');
  for (const file of saved.files) {
    const bytes = await fs.readFile(path.join(root, 'storage', file.name));
    if (bytes.length !== file.bytes || digest(bytes) !== file.sha256) throw new Error(`File archive checksum failed: ${file.name}`);
  }
  const auth = require(path.join(process.env.FIREBASE_CLI_ROOT, 'lib/auth'));
  const account = auth.getGlobalDefaultAccount();
  async function request(url, method = 'GET', body) {
    const token = await auth.getAccessToken(account.tokens.refresh_token, ['https://www.googleapis.com/auth/cloud-platform']);
    const response = await fetch(url, {method, headers: {Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json'}, ...(body ? {body: JSON.stringify(body)} : {})});
    const text = await response.text();
    const value = text ? JSON.parse(text) : {};
    if (!response.ok) throw new Error(`${method} ${new URL(url).pathname}: ${response.status} ${value.error?.message || ''}`);
    return value;
  }
  // Stop if any remote file has been added/replaced after the archive.
  const liveFiles = [];
  let pageToken;
  do {
    const query = new URLSearchParams({maxResults: '1000', ...(pageToken ? {pageToken} : {})});
    const result = await request(`https://storage.googleapis.com/storage/v1/b/${bucketName}/o?${query}`);
    liveFiles.push(...result.items || []);
    pageToken = result.nextPageToken;
  } while (pageToken);
  const known = new Map(saved.files.map(file => [file.name, file]));
  if (liveFiles.length !== known.size || liveFiles.some(file => known.get(file.name)?.metadata.generation !== file.generation)) throw new Error('Cloud storage changed after the archive. Retirement stopped.');
  execFileSync(process.execPath, [path.join(__dirname, 'export_local_backup.js'), root, '--verify-only'], {stdio: 'inherit', env: process.env});
  const listing = await request(`https://cloudfunctions.googleapis.com/v2/projects/${projectId}/locations/-/functions`);
  if (listing.nextPageToken || listing.unreachable?.length) throw new Error('Function inventory is incomplete.');
  const functions = listing.functions || [];
  if (functions.some(item => item.name.split('/').at(-1) !== 'lookupHardcover')) throw new Error('Unexpected functions exist; retirement stopped.');
  await fs.writeFile(path.join(root, 'deployed_functions.json'), JSON.stringify(functions, null, 2));
  for (const item of functions) {
    const download = await request(`https://cloudfunctions.googleapis.com/v2/${item.name}:generateDownloadUrl`, 'POST', {});
    const response = await fetch(download.downloadUrl);
    if (!response.ok) throw new Error('Deployed function source backup failed.');
    await fs.writeFile(path.join(root, `deployed-${item.name.split('/').at(-1)}.zip`), Buffer.from(await response.arrayBuffer()));
  }
  const operations = [];
  for (const item of functions) {
    const operation = await request(`https://cloudfunctions.googleapis.com/v2/${item.name}`, 'DELETE');
    operations.push({service: 'functions', name: operation.name});
    console.log(`Removing ${item.name}`);
  }
  const database = await request(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)`);
  if (database.deleteProtectionState !== 'DELETE_PROTECTION_DISABLED') throw new Error('Database deletion protection is enabled.');
  await fs.writeFile(path.join(root, 'firestore_database.json'), JSON.stringify(database, null, 2));
  const deletion = await request(`https://firestore.googleapis.com/v1/${database.name}?etag=${encodeURIComponent(database.etag)}`, 'DELETE');
  operations.push({service: 'firestore', name: deletion.name});
  console.log('Removing the archived Firestore database.');
  for (const item of liveFiles) {
    await request(`https://storage.googleapis.com/storage/v1/b/${bucketName}/o/${encodeURIComponent(item.name)}?ifGenerationMatch=${item.generation}`, 'DELETE');
  }
  console.log(`Removed ${liveFiles.length} archived storage objects.`);
  await fs.writeFile(path.join(root, 'cloud_retirement_operations.json'), JSON.stringify(operations, null, 2));
  console.log(JSON.stringify(operations));
}
main().catch(error => {console.error(error.message); process.exitCode = 1;});
