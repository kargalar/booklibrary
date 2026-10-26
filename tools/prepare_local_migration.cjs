// Creates an auditable, phone-specific import without modifying either backup.
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');

const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const imageFields = ['coverUrl', 'coverStorageUrl', 'coverPath', 'publisherLogoUrl', 'photoURL'];
const maxImageBytes = 1024 * 1024 * 1024;

async function main() {
  const root = process.argv[2];
  if (!root || !path.isAbsolute(root)) throw new Error('An absolute backup directory is required.');
  const cloud = JSON.parse(await fs.readFile(path.join(root, 'cloud_backup.json')));
  const phone = JSON.parse(await fs.readFile(path.join(root, 'phone_migration_backup.json')));
  const staging = path.join(root, 'staging');
  await fs.mkdir(staging, {recursive: true});
  const documents = structuredClone(cloud.documents);
  // Server records are authoritative unless the phone explicitly has a pending
  // write. Stale, deleted cache records remain in a separate recovery archive.
  for (const key of phone.pendingPaths) documents[key] = phone.documents[key];
  const files = [];
  async function include(name, source) {
    const bytes = await fs.readFile(source);
    const destination = path.join(staging, 'local_migration_files', name);
    await fs.mkdir(path.dirname(destination), {recursive: true});
    await fs.writeFile(destination, bytes);
    files.push({name, bytes: bytes.length, sha256: hash(bytes)});
  }
  for (const item of cloud.files) {
    const source = path.join(root, 'storage', item.name);
    if (hash(await fs.readFile(source)) !== item.sha256) throw new Error(`Archive checksum failed: ${item.name}`);
    await include(item.name, source);
  }
  await include('recovery/phone_cache.json', path.join(root, 'phone_migration_backup.json'));
  const urls = new Set();
  for (const document of Object.values(documents)) {
    for (const key of imageFields) {
      const url = document[key];
      if (typeof url === 'string' && /^https?:/.test(url)) urls.add(url);
    }
  }
  const mapped = new Map();
  for (const item of cloud.files) {
    const original = item.metadata?.metadata?.sourceCoverUrl;
    if (original) mapped.set(original, item.name);
  }
  const cachedImages = path.join(root, 'native', 'app_flutter', 'cover_cache');
  for (const name of await fs.readdir(cachedImages)) {
    if (!name.endsWith('.cover')) continue;
    const url = Buffer.from(name.slice(0, -6), 'base64url').toString('utf8');
    if (!/^https?:/.test(url) || mapped.has(url)) continue;
    const relative = `cached_images/${hash(url)}.img`;
    await include(relative, path.join(cachedImages, name));
    mapped.set(url, relative);
  }
  const errors = [];
  const tasks = [...urls];
  let index = 0;
  let total = files.filter(file => /^(covers|cached_images|remote_images)\//.test(file.name)).reduce((sum, file) => sum + file.bytes, 0);
  let downloaded = 0;
  async function worker() {
    while (index < tasks.length) {
      const url = tasks[index++];
      if (mapped.has(url)) continue;
      const parsed = new URL(url);
      if (parsed.hostname === 'firebasestorage.googleapis.com') {
        const name = decodeURIComponent(parsed.pathname.split('/o/')[1] || '');
        if (files.some(file => file.name === name)) mapped.set(url, name);
        else errors.push({url, reason: 'Storage object is absent from the backup.'});
        continue;
      }
      const name = `remote_images/${hash(url)}.img`;
      const cached = path.join(root, name);
      try {
        let bytes;
        try { bytes = await fs.readFile(cached); } catch (error) { if (error.code !== 'ENOENT') throw error; }
        if (!bytes) {
          const response = await fetch(url, {signal: AbortSignal.timeout(20000), headers: {Accept: 'image/*'}});
          if (!response.ok || !response.headers.get('content-type')?.startsWith('image/')) throw new Error(`Image response ${response.status}`);
          if (Number(response.headers.get('content-length') || 0) > 10 * 1024 * 1024) throw new Error('Image exceeds 10 MB.');
          bytes = Buffer.from(await response.arrayBuffer());
          if (!bytes.length || bytes.length > 10 * 1024 * 1024) throw new Error('Invalid image size.');
          await fs.mkdir(path.dirname(cached), {recursive: true});
          await fs.writeFile(cached, bytes);
        }
        if (total + bytes.length >= maxImageBytes) throw new Error('Combined image budget reached 1 GB.');
        total += bytes.length;
        await include(name, cached);
        mapped.set(url, name);
        downloaded++;
      } catch (error) { errors.push({url, reason: error.message}); }
      if ((downloaded + errors.length) % 100 === 0) console.log(`Images: ${downloaded} local, ${errors.length} unavailable`);
    }
  }
  await Promise.all(Array.from({length: 12}, worker));
  const imagePaths = Object.fromEntries(mapped);
  // Paths are resolved on the phone, never hardcoded to a workstation directory.
  const archive = {schemaVersion: 1, user: phone.user, documents, files, imagePaths};
  await fs.writeFile(path.join(staging, 'local_migration_input.json'), JSON.stringify(archive));
  const report = {documents: Object.keys(documents).length, files: files.length, imageBytes: total, imagesAvailable: mapped.size, unavailableImages: errors, recoveryCacheOnly: Object.keys(phone.documents).filter(key => !documents[key])};
  await fs.writeFile(path.join(root, 'migration_report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({documents: report.documents, files: report.files, imageBytes: total, imagesAvailable: mapped.size, unavailableImages: errors.length, preservedCacheOnly: report.recoveryCacheOnly.length}));
}
main().catch(error => {console.error(error.message); process.exitCode = 1;});
