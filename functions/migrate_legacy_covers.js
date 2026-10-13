const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');
const {initializeApp} = require('firebase-admin/app');
const {FieldValue, getFirestore} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');

const projectId = 'booklibrary-kargalar-2026';
const bucketName = 'booklibrary-kargalar-2026.firebasestorage.app';
const localCoverPattern = /^\/data\/user\/0\/com\.example\.booklibrary\/app_flutter\/covers\//;
const args = new Set(process.argv.slice(2));
const sourceArgumentIndex = process.argv.indexOf('--source');
const sourceDir = path.resolve(
  sourceArgumentIndex === -1
    ? path.join(__dirname, '..', 'cover-migration', 'originals')
    : process.argv[sourceArgumentIndex + 1],
);

initializeApp({projectId, storageBucket: bucketName});
const db = getFirestore();
const bucket = getStorage().bucket(bucketName);

function isLegacyCover(value) {
  return typeof value === 'string' && localCoverPattern.test(value);
}

function downloadUrl(objectName, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(objectName)}?alt=media&token=${token}`;
}

async function main() {
  const snapshot = await db.collection('libraryBooks').get();
  const candidates = snapshot.docs
    .map((doc) => ({
      id: doc.id,
      data: doc.data(),
    }))
    .filter(({data}) => isLegacyCover(data.coverPath));

  const missing = [];
  for (const entry of candidates) {
    const source = path.join(sourceDir, `${entry.id}.jpg`);
    try {
      const stat = await fs.stat(source);
      if (!stat.isFile() || stat.size === 0) missing.push(source);
    } catch {
      missing.push(source);
    }
  }
  if (missing.length) {
    throw new Error(`Eksik kapak dosyaları:\n${missing.join('\n')}`);
  }

  console.log(`Aday kapak: ${candidates.length}`);
  console.log(`Kaynak klasörü: ${sourceDir}`);
  if (args.has('--dry-run')) return;

  const updates = [];
  for (const entry of candidates) {
    const uid = entry.data.libraryId;
    const objectName = `covers/${uid}/${entry.id}.jpg`;
    const token = crypto.randomUUID();
    const file = bucket.file(objectName);
    const bytes = await fs.readFile(path.join(sourceDir, `${entry.id}.jpg`));
    await file.save(bytes, {
      resumable: false,
      metadata: {
        contentType: 'image/jpeg',
        cacheControl: 'public,max-age=31536000',
        metadata: {
          firebaseStorageDownloadTokens: token,
          legacyCoverPath: entry.data.coverPath,
        },
      },
    });

    const [metadata] = await file.getMetadata();
    if (Number(metadata.size) !== bytes.length) {
      throw new Error(`Kapak doğrulanamadı: ${entry.id}`);
    }
    updates.push({
      ref: db.collection('libraryBooks').doc(entry.id),
      data: {
        coverPath: downloadUrl(objectName, token),
        coverStoragePath: objectName,
        legacyCoverPath: entry.data.coverPath,
        updatedAt: FieldValue.serverTimestamp(),
      },
    });
    console.log(`Yüklendi ${updates.length}/${candidates.length}: ${entry.id}`);
  }

  const batch = db.batch();
  for (const update of updates) batch.set(update.ref, update.data, {merge: true});
  await batch.commit();
  console.log(`Firestore bağlantısı güncellendi: ${updates.length}`);
}

main().catch((error) => {
  console.error(error.stack || error.message || error);
  process.exitCode = 1;
});
