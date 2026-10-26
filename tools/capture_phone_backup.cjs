// Copies archives prepared by the temporary migration bridge via its debug VM.
// This is used only before installing the final, Firebase-free release.
const {execFileSync} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const {Readable} = require('node:stream');
const {pipeline} = require('node:stream/promises');

async function main() {
  const output = process.argv[2];
  if (!output || !path.isAbsolute(output)) throw new Error('An absolute backup directory is required.');
  const log = execFileSync('adb', ['logcat', '-d', '-s', 'flutter'], {encoding: 'utf8'});
  const secret = [...log.matchAll(/BACKUP_TRANSFER_TOKEN ([a-f0-9]+)/g)].at(-1)?.[1];
  if (!secret) throw new Error('Migration bridge backup is not ready.');  execFileSync('adb', ['forward', 'tcp:38743', 'tcp:38743']);
  for (const [endpoint, name] of [['phone.json', 'phone_migration_backup.json'], ['private.tar', 'phone_private_backup.tar']]) {
    const response = await fetch(`http://127.0.0.1:38743/${endpoint}`, {headers: {authorization: secret}});
    if (!response.ok) throw new Error(`Phone backup download failed: ${response.status}`);
    await pipeline(Readable.fromWeb(response.body), fs.createWriteStream(path.join(output, name)));
    console.log(`Saved ${name}: ${fs.statSync(path.join(output, name)).size} bytes`);
  }
  execFileSync('adb', ['forward', '--remove', 'tcp:38743']);

}
main().catch(error => {console.error(error.message); process.exitCode = 1;});
