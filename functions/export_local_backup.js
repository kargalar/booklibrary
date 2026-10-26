// Read-only archival export. No Firebase documents or objects are changed.
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');

const projectId = 'booklibrary-kargalar-2026';
const bucketName = `${projectId}.firebasestorage.app`;

async function main() {
  const output = process.argv[2];
  if (!output || !path.isAbsolute(output)) throw new Error('An absolute backup directory is required.');
  await fs.mkdir(output, {recursive: true});
  const cliRoot = process.env.FIREBASE_CLI_ROOT;
  let authClient;
  if (cliRoot) {
    const auth = require(path.join(cliRoot, 'lib/auth'));
    const account = auth.getGlobalDefaultAccount();
    if (!account) throw new Error('Firebase CLI is not signed in.');
    authClient = {};
    authClient.getRequestHeaders = async () => {
      const token = await auth.getAccessToken(account.tokens.refresh_token, ['https://www.googleapis.com/auth/cloud-platform']);
      return new Headers({Authorization: `Bearer ${token.access_token}`});
    };
  }
  if (!authClient) {
    const {GoogleAuth} = require('google-auth-library');
    authClient = await new GoogleAuth({scopes: ['https://www.googleapis.com/auth/cloud-platform']}).getClient();
  }  const documents = {};
  const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
  async function request(url, body) {
    const headers = new Headers(await authClient.getRequestHeaders());
    headers.set('Content-Type', 'application/json');
    const response = await fetch(url, {headers, ...(body ? {method: 'POST', body: JSON.stringify(body)} : {})});
    if (!response.ok) throw new Error(`Firestore export failed: ${response.status} ${await response.text()}`);
    return response.json();
  }
  function decode(value) {
    if ('nullValue' in value) return null;
    if ('stringValue' in value) return value.stringValue;
    if ('booleanValue' in value) return value.booleanValue;
    if ('integerValue' in value) {
      const number = Number(value.integerValue);
      if (!Number.isSafeInteger(number)) throw new Error('Unsafe integer in export.');
      return number;
    }
    if ('doubleValue' in value) return value.doubleValue;
    if ('timestampValue' in value) {
      const seconds = Math.floor(Date.parse(value.timestampValue) / 1000);
      const fraction = value.timestampValue.match(/\.(\d+)Z$/)?.[1] || '';
      return {__type: 'timestamp', seconds, nanoseconds: Number(fraction.padEnd(9, '0'))};
    }
    if ('mapValue' in value) return Object.fromEntries(Object.entries(value.mapValue.fields || {}).map(([key, item]) => [key, decode(item)]));
    if ('arrayValue' in value) return (value.arrayValue.values || []).map(decode);
    if ('referenceValue' in value) return {__type: 'reference', path: value.referenceValue.split('/documents/')[1]};
    if ('geoPointValue' in value) return {__type: 'geoPoint', ...value.geoPointValue};
    if ('bytesValue' in value) return {__type: 'bytes', value: value.bytesValue};
    throw new Error('Unsupported Firestore value.');
  }
  async function collections(parent = '') {
    const ids = [];
    let pageToken;
    do {
      const result = await request(`${base}${parent ? '/' + parent : ''}:listCollectionIds`, {pageSize: 1000, ...(pageToken ? {pageToken} : {})});
      ids.push(...result.collectionIds || []);
      pageToken = result.nextPageToken;
    } while (pageToken);
    return ids;
  }
  async function read(collection) {
    let pageToken;
    do {
      const parameters = new URLSearchParams({pageSize: '1000', showMissing: 'true', ...(pageToken ? {pageToken} : {})});
      const result = await request(`${base}/${collection}?${parameters}`);
      const rows = result.documents || [];
      for (let offset = 0; offset < rows.length; offset += 16) {
        await Promise.all(rows.slice(offset, offset + 16).map(async doc => {
        const docPath = doc.name.split('/documents/')[1];
        if (doc.fields) documents[docPath] = Object.fromEntries(Object.entries(doc.fields).map(([key, value]) => [key, decode(value)]));
        for (const nested of await collections(docPath)) await read(`${docPath}/${nested}`);
        }));
      }
      pageToken = result.nextPageToken;
    } while (pageToken);
  }
  for (const collection of await collections()) {
    await read(collection);
    console.log(`Exported ${collection}: ${Object.keys(documents).length} total records`);
  }
  if (process.argv.includes('--verify-only')) {
    const saved = JSON.parse(await fs.readFile(path.join(output, 'cloud_backup.json')));
    function canonical(value) {
      if (Array.isArray(value)) return value.map(canonical);
      if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
      return value;
    }
    if (JSON.stringify(canonical(documents)) !== JSON.stringify(canonical(saved.documents))) throw new Error('Cloud documents changed after the backup. Cloud removal must stop.');
    console.log(`Verified unchanged cloud data: ${Object.keys(documents).length} records`);
    return;
  }
  const objects = [];
  let storagePage;
  do {
    const query = new URLSearchParams({maxResults: '1000', ...(storagePage ? {pageToken: storagePage} : {})});
    const result = await request(`https://storage.googleapis.com/storage/v1/b/${bucketName}/o?${query}`);
    objects.push(...result.items || []);
    storagePage = result.nextPageToken;
  } while (storagePage);
  await fs.writeFile(path.join(output, 'cloud_documents.json'), JSON.stringify({schemaVersion: 1, documents}));
  const files = [];
  for (const object of objects) {
    const name = object.name;
    const destination = path.resolve(output, 'storage', name);
    if (!destination.startsWith(path.resolve(output, 'storage') + path.sep)) throw new Error('Unsafe storage object path.');
    await fs.mkdir(path.dirname(destination), {recursive: true});
    let cached = false;
    try {
      const existing = await fs.readFile(destination);
      cached = existing.length === Number(object.size) && crypto.createHash('md5').update(existing).digest('base64') === object.md5Hash;
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (!cached) {
      const headers = new Headers(await authClient.getRequestHeaders());
      const response = await fetch(`https://storage.googleapis.com/storage/v1/b/${bucketName}/o/${encodeURIComponent(name)}?alt=media&generation=${object.generation}`, {headers});
      if (!response.ok) throw new Error(`Storage download failed: ${response.status} ${name}`);
      await fs.writeFile(destination, Buffer.from(await response.arrayBuffer()));
    }
    const bytes = await fs.readFile(destination);
    if (bytes.length !== Number(object.size) || crypto.createHash('md5').update(bytes).digest('base64') !== object.md5Hash) throw new Error(`Storage checksum mismatch: ${name}`);
    files.push({name, bytes: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex'), metadata: object});
  }
  const backup = {schemaVersion: 1, exportedAt: new Date().toISOString(), projectId, documents, files};
  const serialized = JSON.stringify(backup);
  await fs.writeFile(path.join(output, 'cloud_backup.json'), serialized, {flag: 'wx'});
  await fs.writeFile(path.join(output, 'cloud_backup.sha256'), crypto.createHash('sha256').update(serialized).digest('hex'));
  console.log(JSON.stringify({documents: Object.keys(documents).length, files: files.length, bytes: files.reduce((sum, file) => sum + file.bytes, 0)}));
}

main().catch(error => {console.error(error.message); process.exitCode = 1;});

