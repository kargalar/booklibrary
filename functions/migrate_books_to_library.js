const {initializeApp} = require('firebase-admin/app');
const {FieldValue, getFirestore, Timestamp} = require('firebase-admin/firestore');

const projectId = process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT || 'booklibrary-kargalar-2026';
initializeApp({projectId});
const db = getFirestore();

const personalFields = new Set([
  'status', 'wishlist', 'coverPath', 'readingFormat', 'audioFormat',
  'readingProgress', 'listeningProgress', 'notes', 'quotes', 'completedAt',
  'borrower', 'borrowerId', 'borrowerUserId', 'loanRequestId', 'loanDue',
  'loanedAt', 'returnedAt', 'createdAt', 'updatedAt',
]);
const structuralFields = new Set([
  'ownerId', 'catalogId', 'libraryOwnerIds', 'libraryId', 'bookId',
  'libraryCount', 'libraryOwnerCounts',
]);
const excludedCanonicalFields = new Set([
  ...personalFields,
  ...structuralFields,
]);
const canonicalFields = new Set([
  'recordType', 'isbn', 'isbn10', 'isbn13', 'subtitle', 'authors',
  'description', 'pageCount', 'subjects', 'tags', 'subjectPlaces',
  'subjectPeople', 'subjectTimes', 'contributions', 'publisher',
  'publishedDate', 'firstPublishDate', 'language', 'languageCode', 'origin',
  'coverUrl', 'editionId', 'workId', 'previewUrl', 'sourceUrl',
  'publisherLogoUrl', 'metadataSource', 'isbnApiData', 'isbnApiEditionData',
  'isbnApiWorkData', 'metadataProviders', 'title', 'author', 'titleSearch',
  'isbnSearches',
]);
const oldStatus = 'Tamamlandı';
const newReadStatus = 'Okundu';
const newToReadStatus = 'Okunacak';
const batchSize = 400;

function meaningful(value) {
  return value !== null && value !== undefined && value !== '' &&
    !(Array.isArray(value) && value.length === 0) &&
    !(isPlainObject(value) && Object.keys(value).length === 0);
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' &&
    !Array.isArray(value) && !(value instanceof Timestamp);
}

function mergeValues(current, incoming) {
  if (!meaningful(current)) return incoming;
  if (Array.isArray(current) && Array.isArray(incoming)) {
    return [...new Map(
      [...current, ...incoming].map((value) => [JSON.stringify(value), value]),
    ).values()];
  }
  if (isPlainObject(current) && isPlainObject(incoming)) {
    return {...incoming, ...current};
  }
  return current;
}

function mergeData(target, source) {
  for (const [key, value] of Object.entries(source)) {
    if (meaningful(value)) target[key] = mergeValues(target[key], value);
  }
  return target;
}

function normalizeText(value) {
  return String(value).normalize('NFC')
    .replace(/[\u00a0\u2007\u202f]/g, ' ')
    .replaceAll('\uFFFD', '')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizeKey(value) {
  return normalizeText(value)
    .toLocaleLowerCase('tr-TR')
    .replaceAll('Ä±', 'i')
    .replace(/[Ã­Ã¬Ã®Ã¯]/g, 'i')
    .replaceAll('ÄŸ', 'g')
    .replaceAll('ÅŸ', 's')
    .replaceAll('Ã¼', 'u')
    .replaceAll('Ã¶', 'o')
    .replaceAll('Ã§', 'c')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function normalizeIsbn(value) {
  const isbn = String(value || '').toUpperCase().replace(/[^0-9X]/g, '');
  if (isbn.length === 10) {
    let sum = 0;
    for (let index = 0; index < 10; index += 1) {
      const digit = isbn[index] === 'X' ? 10 : Number(isbn[index]);
      if (!Number.isInteger(digit)) return null;
      sum += digit * (10 - index);
    }
    return sum % 11 === 0 ? isbn : null;
  }
  if (isbn.length === 13) {
    let sum = 0;
    for (let index = 0; index < 13; index += 1) {
      const digit = Number(isbn[index]);
      if (!Number.isInteger(digit)) return null;
      sum += digit * (index % 2 === 0 ? 1 : 3);
    }
    return sum % 10 === 0 ? isbn : null;
  }
  return null;
}

function isbnSearches(data) {
  return [...new Set(['isbn', 'isbn10', 'isbn13']
    .map((field) => normalizeIsbn(data[field]))
    .filter(Boolean))];
}

function canonicalIdFromData(data) {
  const catalogId = typeof data.catalogId === 'string' ? data.catalogId.trim() : '';
  if (catalogId) return catalogId.startsWith('book_') ? catalogId : `book_${catalogId}`;
  const isbns = isbnSearches(data);
  if (isbns.length) return `book_isbn_${isbns[0]}`;
  return `book_title_${encodeURIComponent(normalizeKey(data.title || ''))}_` +
    `${encodeURIComponent(normalizeKey(data.author || ''))}`;
}

function canonicalIdFromCatalog(document) {
  return document.id.startsWith('book_') ? document.id : `book_${document.id}`;
}

function canonicalSource(data, {legacy = false} = {}) {
  const source = {};
  for (const [key, value] of Object.entries(data)) {
    if (!excludedCanonicalFields.has(key)) source[key] = value;
  }
  if (meaningful(data.createdAt)) source.createdAt = data.createdAt;
  if (!legacy && meaningful(data.updatedAt)) source.updatedAt = data.updatedAt;
  return source;
}

function personalSource(data) {
  const source = {};
  for (const key of personalFields) {
    if (meaningful(data[key])) source[key] = data[key];
  }
  if (source.status === oldStatus) source.status = newReadStatus;
  return source;
}

function relationSource(data) {
  const source = {};
  for (const [key, value] of Object.entries(data)) {
    if (!canonicalFields.has(key) && !structuralFields.has(key)) source[key] = value;
  }
  if (source.status === oldStatus) source.status = newReadStatus;
  return source;
}

function safeRelationId(ownerId, bookId) {
  return `catalog_${encodeURIComponent(ownerId)}_${encodeURIComponent(bookId)}`;
}

function strings(value) {
  return Array.isArray(value) ? value.filter((item) => typeof item === 'string' && item) : [];
}

async function readAll(references) {
  const snapshots = [];
  for (let index = 0; index < references.length; index += batchSize) {
    snapshots.push(...await db.getAll(...references.slice(index, index + batchSize)));
  }
  return snapshots;
}

async function commitOperations(operations, dryRun) {
  if (dryRun) return;
  for (let index = 0; index < operations.length; index += batchSize) {
    const batch = db.batch();
    for (const operation of operations.slice(index, index + batchSize)) {
      if (operation.type === 'delete') batch.delete(operation.ref);
      else batch.set(operation.ref, operation.data, {merge: true});
    }
    await batch.commit();
  }
}

async function main() {
  const dryRun = process.argv.includes('--dry-run');
  const [bookSnapshot, relationSnapshot, catalogSnapshot, loanSnapshot, notificationSnapshot] = await Promise.all([
    db.collection('books').get(),
    db.collection('libraryBooks').get(),
    db.collection('catalogBooks').get(),
    db.collection('loanRequests').get(),
    db.collection('notifications').get(),
  ]);
  const canonical = new Map();
  const relations = new Map();
  const legacyBooks = [];
  const catalogBooks = [];
  const canonicalRatingSources = new Set();

  const addCanonical = (bookId, data, options) => {
    const entry = canonical.get(bookId) || {data: {}};
    mergeData(entry.data, canonicalSource(data, options));
    canonical.set(bookId, entry);
  };
  const addRelation = (relationId, libraryId, bookId, data, exists = false) => {
    const entry = relations.get(relationId) || {data: {}, exists};
    if (entry.data.bookId && entry.data.bookId !== bookId) {
      throw new Error(`İlişki ID çakışması: ${relationId}`);
    }
    if (entry.data.libraryId && entry.data.libraryId !== libraryId) {
      throw new Error(`Kütüphane ID çakışması: ${relationId}`);
    }
    mergeData(entry.data, data);
    entry.data.libraryId = libraryId;
    entry.data.bookId = bookId;
    relations.set(relationId, entry);
  };

  for (const document of relationSnapshot.docs) {
    const data = document.data();
    if (typeof data.libraryId !== 'string' || typeof data.bookId !== 'string') {
      throw new Error(`Geçersiz libraryBooks kaydı: ${document.ref.path}`);
    }
    addRelation(document.id, data.libraryId, data.bookId, relationSource(data), true);
    addCanonical(data.bookId, data);
  }

  for (const document of bookSnapshot.docs) {
    const data = document.data();
    if (typeof data.ownerId !== 'string' || !data.ownerId) {
      const misplacedPersonalFields = [...personalFields].filter((field) =>
        !['createdAt', 'updatedAt'].includes(field) && meaningful(data[field]));
      if (misplacedPersonalFields.length) {
        throw new Error(
          `İlişkisi bulunmayan kişisel alanlar var: ${document.ref.path} (${misplacedPersonalFields.join(', ')})`,
        );
      }
      addCanonical(document.id, data);
      canonicalRatingSources.add(document.id);
      continue;
    }
    let bookId = canonicalIdFromData(data);
    if (bookId === document.id) {
      bookId = `book_migrated_${document.id}`;
    }
    addCanonical(bookId, data, {legacy: true});
    addRelation(document.id, data.ownerId, bookId, personalSource(data));
    legacyBooks.push(document);
  }

  for (const document of catalogSnapshot.docs) {
    const data = document.data();
    const bookId = canonicalIdFromCatalog(document);
    addCanonical(bookId, data);
    catalogBooks.push(document);
    for (const ownerId of strings(data.libraryOwnerIds)) {
      const alreadyLinked = [...relations.values()].some((relation) =>
        relation.data.libraryId === ownerId && relation.data.bookId === bookId);
      if (!alreadyLinked) {
        addRelation(
          safeRelationId(ownerId, bookId),
          ownerId,
          bookId,
          {...personalSource(data), status: personalSource(data).status || newToReadStatus},
        );
      }
    }
  }

  const missingReferences = [...loanSnapshot.docs, ...notificationSnapshot.docs]
    .filter((document) => !relations.has(document.data().bookId))
    .map((document) => document.ref.path);
  if (missingReferences.length) {
    throw new Error(
      `İlişkisi bulunmayan ödünç/bildirim kayıtları var; veri kaybını önlemek için durduruldu: ${missingReferences.join(', ')}`,
    );
  }

  for (const [bookId, entry] of canonical) {
    entry.data.recordType = 'book';
    const ownerCounts = {};
    let count = 0;
    for (const relation of relations.values()) {
      if (relation.data.bookId !== bookId) continue;
      const ownerId = relation.data.libraryId;
      if (typeof ownerId !== 'string' || !ownerId) continue;
      count += 1;
      ownerCounts[ownerId] = (ownerCounts[ownerId] || 0) + 1;
    }
    entry.data.libraryCount = count;
    entry.data.libraryOwnerCounts = ownerCounts;
    if (!meaningful(entry.data.createdAt)) entry.data.createdAt = Timestamp.now();
    if (!meaningful(entry.data.updatedAt)) entry.data.updatedAt = Timestamp.now();
  }

  const relationWrites = [];
  for (const entry of relations.values()) {
    entry.data.status = entry.data.status === oldStatus
      ? newReadStatus
      : (entry.data.status || newToReadStatus);
    if (typeof entry.data.wishlist !== 'boolean') entry.data.wishlist = false;
    if (!meaningful(entry.data.createdAt)) entry.data.createdAt = Timestamp.now();
    if (!meaningful(entry.data.updatedAt)) entry.data.updatedAt = Timestamp.now();
    for (const field of canonicalFields) entry.data[field] = FieldValue.delete();
    for (const field of ['ownerId', 'catalogId', 'libraryOwnerIds']) {
      entry.data[field] = FieldValue.delete();
    }
  }

  for (const entry of canonical.values()) {
    for (const field of ['ownerId', 'catalogId', 'libraryOwnerIds', ...personalFields]) {
      if (field !== 'createdAt' && field !== 'updatedAt') {
        entry.data[field] = FieldValue.delete();
      }
    }
  }

  const relationRefs = [...relations.entries()].map(([id]) => db.collection('libraryBooks').doc(id));
  const existingRelationRatings = new Set();
  for (const snapshot of await Promise.all(relationRefs.map((ref) => ref.collection('ratings').get()))) {
    for (const rating of snapshot.docs) existingRelationRatings.add(rating.ref.path);
  }
  const ratingWrites = new Map();
  const ratingDeletes = [];
  const addRating = (relationId, rating) => {
    const destination = db.collection('libraryBooks').doc(relationId)
      .collection('ratings').doc(rating.id);
    if (existingRelationRatings.has(destination.path)) return;
    ratingWrites.set(destination.path, {ref: destination, data: rating.data()});
  };

  for (const legacy of legacyBooks) {
    const ratings = await legacy.ref.collection('ratings').get();
    for (const rating of ratings.docs) {
      addRating(legacy.id, rating);
      ratingDeletes.push({type: 'delete', ref: rating.ref});
    }
  }

  const orphanCanonicalRatings = [];
  for (const bookId of canonicalRatingSources) {
    const ratings = await db.collection('books').doc(bookId).collection('ratings').get();
    const destinationIds = [...relations.entries()]
      .filter(([, relation]) => relation.data.bookId === bookId)
      .map(([id]) => id);
    if (ratings.size && !destinationIds.length) orphanCanonicalRatings.push(bookId);
    for (const rating of ratings.docs) {
      for (const relationId of destinationIds) addRating(relationId, rating);
      ratingDeletes.push({type: 'delete', ref: rating.ref});
    }
  }
  if (orphanCanonicalRatings.length) {
    throw new Error(
      `İlişkisi bulunmayan canonical puanları var; veri kaybını önlemek için durduruldu: ${orphanCanonicalRatings.join(', ')}`,
    );
  }

  const writes = [
    ...[...canonical.entries()].map(([id, entry]) => ({
      type: 'set', ref: db.collection('books').doc(id), data: entry.data,
    })),
    ...[...relations.entries()].map(([id, entry]) => ({
      type: 'set', ref: db.collection('libraryBooks').doc(id), data: entry.data,
    })),
    ...ratingWrites.values(),
  ];
  const oldDataDeletes = [
    ...legacyBooks.map((document) => ({type: 'delete', ref: document.ref})),
    ...catalogBooks.map((document) => ({type: 'delete', ref: document.ref})),
    ...ratingDeletes,
  ];

  console.log(JSON.stringify({
    dryRun,
    canonicalBooks: canonical.size,
    libraryBooks: relations.size,
    legacyBooks: legacyBooks.length,
    catalogBooks: catalogBooks.length,
    ratingsToCopy: ratingWrites.size,
    oldDocumentsToDelete: oldDataDeletes.length,
  }, null, 2));
  if (dryRun) return;

  await commitOperations(writes, false);
  const verification = await readAll([
    ...[...canonical.keys()].map((id) => db.collection('books').doc(id)),
    ...[...relations.keys()].map((id) => db.collection('libraryBooks').doc(id)),
    ...[...ratingWrites.values()].map(({ref}) => ref),
  ]);
  if (verification.some((snapshot) => !snapshot.exists)) {
    throw new Error('Migration doğrulaması başarısız; eski veriler silinmedi.');
  }
  await commitOperations(oldDataDeletes, false);
  console.log('Migration tamamlandı; eski kitap ve katalog kayıtları silindi.');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
