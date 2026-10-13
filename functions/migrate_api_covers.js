const crypto = require('node:crypto');
const {initializeApp} = require('firebase-admin/app');
const {FieldValue, getFirestore} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');

const projectId = 'booklibrary-kargalar-2026';
const bucketName = 'booklibrary-kargalar-2026.firebasestorage.app';
const localCoverPattern = /^\/data\/user\/0\/com\.example\.booklibrary\/app_flutter\/covers\//;
const storageUrlPrefix = `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/`;
const args = new Set(process.argv.slice(2));

initializeApp({projectId, storageBucket: bucketName});
const db = getFirestore();
const bucket = getStorage().bucket(bucketName);

function isHttpUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'http:' || url.protocol === 'https:';
  } catch {
    return false;
  }
}

function isStorageUrl(value) {
  return typeof value === 'string' && value.startsWith(storageUrlPrefix);
}

function isLocalCover(value) {
  return typeof value === 'string' && localCoverPattern.test(value);
}

function sourceUrl(relation, canonical) {
  const currentPath = relation.coverPath;
  if (isLocalCover(currentPath) || isStorageUrl(currentPath)) return null;
  if (isHttpUrl(currentPath)) return currentPath;
  if (isStorageUrl(canonical.coverUrl)) return canonical.coverUrl;
  return isHttpUrl(canonical.coverUrl) ? canonical.coverUrl : null;
}

function downloadUrl(objectName, token) {
  return `${storageUrlPrefix}${encodeURIComponent(objectName)}?alt=media&token=${token}`;
}

async function downloadImage(url) {
  const response = await fetch(url, {headers: {'Accept': 'image/*'}});
  if (!response.ok) throw new Error(`Cover download failed (${response.status}): ${url}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length === 0) throw new Error(`Empty cover response: ${url}`);
  const contentType = (response.headers.get('content-type') || 'image/jpeg')
    .split(';', 1)[0]
    .trim();
  if (!contentType.startsWith('image/')) {
    throw new Error(`Cover response is not an image (${contentType}): ${url}`);
  }
  return {bytes, contentType};
}

async function main() {
  const [relations, books] = await Promise.all([
    db.collection('libraryBooks').get(),
    db.collection('books').get(),
  ]);
  const canonicalById = new Map(books.docs.map((doc) => [doc.id, doc.data()]));
  const candidates = relations.docs
    .map((doc) => {
      const relation = doc.data();
      const canonical = canonicalById.get(relation.bookId) || {};
      return {
        id: doc.id,
        uid: relation.libraryId,
        relation,
        url: sourceUrl(relation, canonical),
      };
    })
    .filter((entry) => entry.uid && entry.url);

  console.log(`API cover candidates: ${candidates.length}`);
  if (args.has('--dry-run')) return;

  const downloads = [];
  for (const [index, candidate] of candidates.entries()) {
    downloads.push({candidate, image: await downloadImage(candidate.url)});
    console.log(`Downloaded ${index + 1}/${candidates.length}: ${candidate.id}`);
  }

  const uploaded = [];
  try {
    const updates = [];
    for (const [index, entry] of downloads.entries()) {
      const {candidate, image} = entry;
      const objectName = `covers/${candidate.uid}/${candidate.id}.jpg`;
      const token = crypto.randomUUID();
      const file = bucket.file(objectName);
      await file.save(image.bytes, {
        resumable: false,
        metadata: {
          contentType: image.contentType,
          cacheControl: 'public,max-age=31536000',
          metadata: {
            firebaseStorageDownloadTokens: token,
            sourceCoverUrl: candidate.url,
          },
        },
      });
      const [metadata] = await file.getMetadata();
      if (Number(metadata.size) !== image.bytes.length) {
        throw new Error(`Cover verification failed: ${candidate.id}`);
      }
      uploaded.push(file);
      updates.push({
        ref: db.collection('libraryBooks').doc(candidate.id),
        data: {
          coverPath: downloadUrl(objectName, token),
          coverStoragePath: objectName,
          coverSourceUrl: candidate.url,
          updatedAt: FieldValue.serverTimestamp(),
        },
      });
      console.log(`Uploaded ${index + 1}/${downloads.length}: ${candidate.id}`);
    }

    const batch = db.batch();
    for (const update of updates) batch.set(update.ref, update.data, {merge: true});
    await batch.commit();
    console.log(`Firestore relations updated: ${updates.length}`);
  } catch (error) {
    await Promise.all(uploaded.map((file) => file.delete().catch(() => {})));
    throw error;
  }
}

main().catch((error) => {
  console.error(error.stack || error.message || error);
  process.exitCode = 1;
});
