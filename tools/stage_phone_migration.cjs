const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');

async function main() {
  const root = process.argv[2];
  if (!root || !path.isAbsolute(root)) throw new Error('An absolute staging directory is required.');
  const archivePath = path.join(root, 'local_migration_input.json');
  const archive = JSON.parse(await fs.readFile(archivePath));
  const log = execFileSync('adb', ['logcat', '-d', '-s', 'flutter'], {encoding: 'utf8'});
  const token = [...log.matchAll(/BACKUP_TRANSFER_TOKEN ([a-f0-9]+)/g)].at(-1)?.[1];
  if (!token) throw new Error('The migration bridge is not ready.');
  execFileSync('adb', ['forward', 'tcp:38743', 'tcp:38743']);
  async function upload(relative, bytes) {
    const response = await fetch(`http://127.0.0.1:38743/stage/${relative}`, {method: 'POST', headers: {authorization: token}, body: bytes});
    if (!response.ok || await response.text() !== 'saved') throw new Error(`Phone staging failed: ${relative}`);
  }
  let index = 0;
  let uploadedBytes = 0;
  async function worker() {
    while (index < archive.files.length) {
      const file = archive.files[index++];
      const bytes = await fs.readFile(path.join(root, 'local_migration_files', file.name));
      if (bytes.length !== file.bytes || crypto.createHash('sha256').update(bytes).digest('hex') !== file.sha256) throw new Error(`Staging checksum mismatch: ${file.name}`);
      await upload(`local_migration_files/${file.name}`, bytes);
      uploadedBytes += bytes.length;
    }
  }
  await Promise.all(Array.from({length: 8}, worker));
  await upload('local_migration_input.json', await fs.readFile(archivePath));
  execFileSync('adb', ['forward', '--remove', 'tcp:38743']);
  console.log(JSON.stringify({stagedFiles: archive.files.length, bytes: uploadedBytes, documents: Object.keys(archive.documents).length}));
}
main().catch(error => {console.error(error.message); process.exitCode = 1;});
