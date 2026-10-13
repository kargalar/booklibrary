const crypto = require('node:crypto');
const {initializeApp} = require('firebase-admin/app');
const {FieldValue, getFirestore} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');

const projectId = 'booklibrary-kargalar-2026';
const bucketName = 'booklibrary-kargalar-2026.firebasestorage.app';
const storageUrlPrefix = `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/`;
const args = new Set(process.argv.slice(2));

initializeApp({projectId, storageBucket: bucketName});
const db = getFirestore();
const bucket = getStorage().bucket(bucketName);

function downloadUrl(objectName, token) {
  return `${storageUrlPrefix}${encodeURIComponent(objectName)}?alt=media&token=${token}`;
}

async function main() {
  const snapshot = await db.collection('libraryBooks').get();
  const candidates = snapshot.docs
    .map((doc) => ({id: doc.id, data: doc.data()}))
    .filter(({data}) =>
      typeof data.coverSourceUrl === 'string' &&
      typeof data.coverStoragePath === 'string' &&
      data.coverStoragePath.startsWith('covers/'),
    );

  console.log(`API cover token candidates: ${candidates.length}`);
  if (args.has('--dry-run')) return;

  const updates = [];
  for (const [index, candidate] of candidates.entries()) {
    const objectName = candidate.data.coverStoragePath;
    const file = bucket.file(objectName);
    const token = crypto.randomUUID();
    const [current] = await file.getMetadata();
    await file.setMetadata({
      metadata: {
        ...current.metadata,
        firebaseStorageDownloadTokens: token,
      },
    });
    const [verified] = await file.getMetadata();
    if (verified.metadata?.firebaseStorageDownloadTokens !== token) {
      throw new Error(`Token verification failed: ${candidate.id}`);
    }
    updates.push({
      ref: db.collection('libraryBooks').doc(candidate.id),
      data: {
        coverPath: downloadUrl(objectName, token),
        updatedAt: FieldValue.serverTimestamp(),
      },
    });
    console.log(`Token repaired ${index + 1}/${candidates.length}: ${candidate.id}`);
  }

  const batch = db.batch();
  for (const update of updates) batch.set(update.ref, update.data, {merge: true});
  await batch.commit();
  console.log(`Firestore relations updated: ${updates.length}`);
}

main().catch((error) => {
  console.error(error.stack || error.message || error);
  process.exitCode = 1;
});
