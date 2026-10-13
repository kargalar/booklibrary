const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeApp} = require('firebase-admin/app');
const {FieldValue, getFirestore} = require('firebase-admin/firestore');

const projectId = process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT || 'booklibrary-kargalar-2026';
const root = path.resolve(__dirname, '..');
const sourceFile = resolvePath(argumentValue('--source-file') ||
  path.join('bookdatascraping', '1k', 'output', 'books.jsonl'));
const sourceLabel = firstText(argumentValue('--source-label')) || '1000kitap';
const defaultKeyFile = path.join(root, 'isbn_api');
const args = new Set(process.argv.slice(2));
const dryRun = args.has('--dry-run');
const skipIsbnDb = args.has('--skip-isbndb');
const limit = argumentNumber('--limit');

initializeApp({projectId});
const db = getFirestore();

let lastIsbnDbRequest = 0;
let lastOpenLibraryRequest = 0;

function argumentNumber(prefix) {
  const value = process.argv.find((item) => item.startsWith(`${prefix}=`));
  const number = Number(value?.substring(prefix.length + 1));
  return Number.isInteger(number) && number > 0 ? number : null;
}

function argumentValue(prefix) {
  const value = process.argv.find((item) => item.startsWith(`${prefix}=`));
  return value?.slice(prefix.length + 1) || '';
}

function resolvePath(value) {
  if (path.isAbsolute(value)) return value;
  const workingDirectoryPath = path.resolve(process.cwd(), value);
  return fs.existsSync(workingDirectoryPath) ? workingDirectoryPath : path.resolve(root, value);
}

function text(value) {
  const normalized = String(value ?? '').normalize('NFC').replace(/\s+/g, ' ').trim();
  return normalized && normalized.toLowerCase() !== 'none' ? normalized : '';
}

function key(value) {
  return text(value).toLocaleLowerCase('tr-TR').normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/ı/g, 'i')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function validIsbn(value) {
  const isbn = String(value ?? '').toUpperCase().replace(/[^0-9X]/g, '');
  if (isbn.length === 10) {
    let total = 0;
    for (let index = 0; index < isbn.length; index += 1) {
      const digit = isbn[index] === 'X' ? 10 : Number(isbn[index]);
      if (!Number.isInteger(digit)) return null;
      total += digit * (10 - index);
    }
    return total % 11 === 0 ? isbn : null;
  }
  if (isbn.length === 13) {
    let total = 0;
    for (let index = 0; index < isbn.length; index += 1) {
      const digit = Number(isbn[index]);
      if (!Number.isInteger(digit)) return null;
      total += digit * (index % 2 === 0 ? 1 : 3);
    }
    return total % 10 === 0 ? isbn : null;
  }
  return null;
}

function isbnVariants(value) {
  const isbn = validIsbn(value);
  if (!isbn) return [];
  const variants = new Set([isbn]);
  if (isbn.length === 10) {
    const body = `978${isbn.slice(0, 9)}`;
    const sum = [...body].reduce(
      (total, digit, index) => total + Number(digit) * (index % 2 === 0 ? 1 : 3),
      0,
    );
    variants.add(`${body}${(10 - sum % 10) % 10}`);
  } else if (isbn.startsWith('978')) {
    const body = isbn.slice(3, 12);
    const sum = [...body].reduce(
      (total, digit, index) => total + Number(digit) * (10 - index),
      0,
    );
    const check = (11 - sum % 11) % 11;
    variants.add(`${body}${check === 10 ? 'X' : check}`);
  }
  return [...variants];
}

function asStrings(value, maximum = 24) {
  const values = Array.isArray(value) ? value : value == null ? [] : [value];
  return [...new Map(values.map(text).filter(Boolean).map((item) => [key(item), item])).values()]
    .slice(0, maximum);
}

function firstText(...values) {
  for (const value of values.flat()) {
    const candidate = text(value);
    if (candidate) return candidate;
  }
  return '';
}

function numeric(value) {
  const number = Number(value);
  return Number.isInteger(number) && number > 0 ? number : null;
}

function sourceIsbn(source) {
  return validIsbn(source.isbn13) || validIsbn(source.isbn10) || validIsbn(source.isbn);
}

function sourceKey(source) {
  const isbn = sourceIsbn(source);
  return isbn ? `isbn:${isbnVariants(isbn).sort()[0]}` :
    `title:${key(source.title)}|author:${key(source.author)}`;
}

function titleAuthorKey(data) {
  return `title:${key(data.title)}|author:${key(data.author)}`;
}

function canonicalId(data) {
  const isbn = asStrings([data.isbn, data.isbn10, data.isbn13])
    .map(validIsbn)
    .find(Boolean);
  return isbn ? `book_isbn_${isbn}` :
    `book_title_${encodeURIComponent(key(data.title))}_${encodeURIComponent(key(data.author))}`;
}

function languageName(value) {
  const code = text(value).toLowerCase();
  return ({tur: 'Türkçe', eng: 'İngilizce', deu: 'Almanca', fra: 'Fransızca',
    spa: 'İspanyolca', ita: 'İtalyanca', rus: 'Rusça'})[code] || text(value);
}

function sourceFallback(source) {
  const isbn = sourceIsbn(source);
  return {
    title: firstText(source.title, 'İsimsiz kitap'),
    author: firstText(source.author),
    authors: asStrings(source.author?.split(/[,;]/)),
    isbn: isbn || '',
    isbn10: isbn?.length === 10 ? isbn : '',
    isbn13: isbn?.length === 13 ? isbn : '',
    publisher: firstText(source.publisher),
    publishedDate: firstText(source.publication_date),
    pageCount: numeric(source.pages),
    language: firstText(source.language),
    coverUrl: firstText(source.cover_url),
  };
}

function commonFields(source, metadata, provider, providerData) {
  const fallback = sourceFallback(source);
  const authors = asStrings(metadata.authors);
  const author = firstText(metadata.author, authors.join(', '), fallback.author);
  const isbnValues = [...new Set([
    ...isbnVariants(metadata.isbn), ...isbnVariants(metadata.isbn10),
    ...isbnVariants(metadata.isbn13), ...isbnVariants(fallback.isbn),
  ])];
  const isbn10 = isbnValues.find((value) => value.length === 10) || '';
  const isbn13 = isbnValues.find((value) => value.length === 13) || '';
  const fields = {
    recordType: 'book',
    title: firstText(metadata.title, fallback.title),
    author,
    authors: authors.length ? authors : asStrings(author.split(/[,;]/)),
    titleSearch: key(firstText(metadata.title, fallback.title)),
    isbn: isbn13 || isbn10 || '',
    isbnSearches: isbnValues,
    metadataSource: provider,
    metadataProviders: providerData,
    discoverSource: sourceLabel,
    discoverSourceUrl: firstText(source.book_url),
    discoverSourceTitle: fallback.title,
    discoverSourceAuthor: fallback.author,
    discoverRank: numeric(source.rank),
    libraryCount: 0,
    libraryOwnerCounts: {},
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    discoverImportedAt: FieldValue.serverTimestamp(),
  };
  const optional = {
    isbn10,
    isbn13,
    subtitle: metadata.subtitle,
    description: metadata.description,
    pageCount: metadata.pageCount ?? fallback.pageCount,
    subjects: asStrings(metadata.subjects),
    tags: asStrings(metadata.tags),
    publisher: metadata.publisher || fallback.publisher,
    publishedDate: metadata.publishedDate || fallback.publishedDate,
    firstPublishDate: metadata.firstPublishDate,
    language: metadata.language || fallback.language,
    languageCode: metadata.languageCode,
    coverUrl: metadata.coverUrl || fallback.coverUrl,
    editionId: metadata.editionId,
    workId: metadata.workId,
    sourceUrl: metadata.sourceUrl,
  };
  for (const [name, value] of Object.entries(optional)) {
    if (value !== '' && value != null && (!Array.isArray(value) || value.length)) {
      fields[name] = value;
    }
  }
  return fields;
}

function isbnDbFields(source, book) {
  const authors = asStrings(book.authors);
  const isbn = sourceIsbn(source);
  return commonFields(source, {
    title: firstText(book.title, book.title_long),
    author: authors.join(', '),
    authors,
    isbn: isbn || '',
    isbn10: firstText(book.isbn10),
    isbn13: firstText(book.isbn13),
    subtitle: firstText(book.subtitle),
    description: firstText(book.synopsis, book.overview, book.excerpt),
    pageCount: numeric(book.pages),
    subjects: asStrings(book.subjects),
    publisher: firstText(book.publisher),
    publishedDate: firstText(book.date_published),
    language: languageName(book.language),
    coverUrl: firstText(book.image_original, book.image).replace(/^http:/, 'https:'),
    sourceUrl: isbn ? `https://isbndb.com/book/${isbn}` : '',
  }, 'ISBNdb', {isbnDb: {isbn: isbn || '', id: firstText(book.book_id)}});
}

function openLibraryFields(source, document) {
  const isbns = asStrings(document.isbn, 100).map(validIsbn).filter(Boolean);
  const isbn = sourceIsbn(source) || isbns.find((value) => value.length === 13) || isbns[0] || '';
  const coverId = numeric(document.cover_i);
  const languages = asStrings(document.language, 8).map(languageName);
  return commonFields(source, {
    title: firstText(document.title),
    author: asStrings(document.author_name).join(', '),
    authors: asStrings(document.author_name),
    isbn,
    isbn10: isbns.find((value) => value.length === 10) || '',
    isbn13: isbns.find((value) => value.length === 13) || '',
    subtitle: firstText(document.subtitle),
    pageCount: numeric(document.number_of_pages_median),
    subjects: asStrings(document.subject),
    tags: asStrings(document.subject),
    publisher: firstText(document.publisher),
    publishedDate: firstText(document.publish_date),
    firstPublishDate: numeric(document.first_publish_year)?.toString() || '',
    language: languages.join(', '),
    languageCode: firstText(document.language),
    coverUrl: coverId ? `https://covers.openlibrary.org/b/id/${coverId}-L.jpg?default=false` : '',
    workId: firstText(document.key).split('/').pop(),
    sourceUrl: firstText(document.key) ? `https://openlibrary.org${document.key}` : '',
  }, 'Open Library Search', {openLibrarySearch: {key: firstText(document.key), isbn}});
}

async function waitForSlot(provider) {
  const now = Date.now();
  const last = provider === 'isbnDb' ? lastIsbnDbRequest : lastOpenLibraryRequest;
  const delay = (provider === 'isbnDb' ? 500 : 1100) - (now - last);
  if (delay > 0) await new Promise((resolve) => setTimeout(resolve, delay));
  if (provider === 'isbnDb') lastIsbnDbRequest = Date.now();
  else lastOpenLibraryRequest = Date.now();
}

async function fetchJson(url, headers = {}) {
  const response = await fetch(url, {
    headers: {Accept: 'application/json', 'User-Agent': 'BookLibrary catalog import', ...headers},
    signal: AbortSignal.timeout(15_000),
  });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`${new URL(url).hostname} yanıtı: ${response.status}`);
  return response.json();
}

function isbnDbKey() {
  const fromEnvironment = text(process.env.ISBNDB_API_KEY);
  if (fromEnvironment) return fromEnvironment;
  if (!fs.existsSync(defaultKeyFile)) return '';
  return text(fs.readFileSync(defaultKeyFile, 'utf8'));
}

async function lookupIsbnDb(isbn, apiKey) {
  if (!isbn || !apiKey || skipIsbnDb) return null;
  await waitForSlot('isbnDb');
  const payload = await fetchJson(`https://api2.isbndb.com/book/${encodeURIComponent(isbn)}`, {
    Authorization: apiKey,
  });
  return payload?.book && typeof payload.book === 'object' ? payload.book : null;
}

async function openLibrarySearch(query) {
  const url = new URL('https://openlibrary.org/search.json');
  for (const [name, value] of Object.entries(query)) {
    if (text(value)) url.searchParams.set(name, value);
  }
  url.searchParams.set('limit', '5');
  url.searchParams.set('fields', [
    'title', 'subtitle', 'author_name', 'number_of_pages_median', 'subject',
    'publisher', 'publish_date', 'first_publish_year', 'language', 'isbn',
    'cover_i', 'key',
  ].join(','));
  await waitForSlot('openLibrary');
  const payload = await fetchJson(url.toString());
  return Array.isArray(payload?.docs) ? payload.docs : [];
}

function titleScore(first, second) {
  const a = key(first);
  const b = key(second);
  if (!a || !b) return 0;
  if (a === b) return 1;
  if (a.includes(b) || b.includes(a)) return Math.min(a.length, b.length) / Math.max(a.length, b.length);
  const words = new Set(a.split(' '));
  const other = new Set(b.split(' '));
  const overlap = [...words].filter((word) => other.has(word)).length;
  return overlap === 0 ? 0 : (2 * overlap) / (words.size + other.size);
}

function bestTitleMatch(source, documents) {
  return documents.map((document) => ({document, score: titleScore(source.title, document.title)}))
    .sort((first, second) => second.score - first.score)[0] || null;
}

async function lookupMetadata(source, apiKey) {
  const isbn = sourceIsbn(source);
  if (isbn) {
    const isbnDb = await lookupIsbnDb(isbn, apiKey);
    if (isbnDb) return {fields: isbnDbFields(source, isbnDb), provider: 'ISBNdb'};

    const isbnMatches = await openLibrarySearch({isbn});
    const matchingIsbn = isbnMatches.find((document) =>
      asStrings(document.isbn, 100).some((value) => isbnVariants(value).some(
        (candidate) => isbnVariants(isbn).includes(candidate),
      )),
    );
    if (matchingIsbn) {
      return {fields: openLibraryFields(source, matchingIsbn), provider: 'Open Library Search'};
    }
  }

  const titleMatches = await openLibrarySearch({title: text(source.title), author: text(source.author)});
  const best = bestTitleMatch(source, titleMatches);
  if (best?.score >= 0.72) {
    return {fields: openLibraryFields(source, best.document), provider: 'Open Library Search'};
  }
  return null;
}

function indexBook(index, id, data) {
  for (const value of [data.isbn, data.isbn10, data.isbn13, ...(data.isbnSearches || [])]) {
    for (const isbn of isbnVariants(value)) index.byIsbn.set(isbn, id);
  }
  const titleAuthor = titleAuthorKey(data);
  if (titleAuthor !== 'title:|author:') index.byTitleAuthor.set(titleAuthor, id);
}

function existingMatch(index, source) {
  for (const isbn of isbnVariants(sourceIsbn(source))) {
    const id = index.byIsbn.get(isbn);
    if (id) return {id, match: 'ISBN'};
  }
  const id = index.byTitleAuthor.get(titleAuthorKey(source));
  return id ? {id, match: 'başlık ve yazar'} : null;
}

function writeReport(report) {
  const directory = path.join(__dirname, 'reports');
  fs.mkdirSync(directory, {recursive: true});
  const name = `discover-catalog-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
  const file = path.join(directory, name);
  fs.writeFileSync(file, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  return file;
}

async function main() {
  const apiKey = isbnDbKey();
  if (!skipIsbnDb && !apiKey) throw new Error('ISBNdb anahtarı isbn_api dosyasında veya ISBNDB_API_KEY değişkeninde bulunamadı.');
  const rows = fs.readFileSync(sourceFile, 'utf8').split(/\r?\n/)
    .filter((line) => line.trim())
    .map((line) => JSON.parse(line));
  const sourceRows = limit ? rows.slice(0, limit) : rows;
  const snapshot = await db.collection('books').get();
  const index = {byIsbn: new Map(), byTitleAuthor: new Map()};
  for (const document of snapshot.docs) indexBook(index, document.id, document.data());

  const report = {
    dryRun,
    sourceFile: path.relative(root, sourceFile),
    startedAt: new Date().toISOString(),
    sourceRows: sourceRows.length,
    existing: [],
    duplicateSourceRows: [],
    added: [],
    notFound: [],
    failed: [],
  };
  const seenSources = new Set();
  for (const [offset, source] of sourceRows.entries()) {
    const identity = sourceKey(source);
    if (seenSources.has(identity)) {
      report.duplicateSourceRows.push(summary(source, 'Aynı kaynak listesinde tekrar ediyor.'));
      continue;
    }
    seenSources.add(identity);

    const existing = existingMatch(index, source);
    if (existing) {
      report.existing.push(summary(source, existing.match, existing.id));
      continue;
    }

    try {
      const metadata = await lookupMetadata(source, apiKey);
      if (!metadata) {
        report.notFound.push(summary(source, 'ISBNdb ve Open Library sonuç vermedi.'));
        continue;
      }
      const afterLookup = existingMatch(index, metadata.fields);
      if (afterLookup) {
        report.existing.push(summary(source, `${afterLookup.match} (API sonucu)`, afterLookup.id));
        continue;
      }
      const id = canonicalId(metadata.fields);
      if (!dryRun) await db.collection('books').doc(id).create(metadata.fields);
      indexBook(index, id, metadata.fields);
      report.added.push(summary(source, metadata.provider, id));
    } catch (error) {
      report.failed.push(summary(source, error.message || String(error)));
    }
    if ((offset + 1) % 10 === 0) {
      console.log(`İşlendi: ${offset + 1}/${sourceRows.length}`);
    }
  }
  report.finishedAt = new Date().toISOString();
  report.counts = {
    existing: report.existing.length,
    duplicateSourceRows: report.duplicateSourceRows.length,
    added: report.added.length,
    isbnDb: report.added.filter((item) => item.result === 'ISBNdb').length,
    openLibrary: report.added.filter((item) => item.result === 'Open Library Search').length,
    notFound: report.notFound.length,
    failed: report.failed.length,
  };
  const reportFile = writeReport(report);
  console.log(JSON.stringify({...report.counts, reportFile}, null, 2));
}

function summary(source, result, bookId = '') {
  return {
    title: text(source.title),
    author: text(source.author),
    isbn: sourceIsbn(source) || '',
    result,
    ...(bookId ? {bookId} : {}),
  };
}

function selfTest() {
  assert.equal(validIsbn('978-975-07-6609-1'), '9789750766091');
  assert.deepEqual(isbnVariants('0439554934').sort(), ['0439554934', '9780439554930']);
  assert.equal(titleScore('Küçük Prens', 'Kucuk Prens'), 1);
  assert.equal(canonicalId({isbn13: '9789750766091'}), 'book_isbn_9789750766091');
  console.log('Discover catalog import self-test passed.');
}

if (args.has('--self-test')) selfTest();
else main().catch((error) => {
  console.error(error.stack || error.message || error);
  process.exitCode = 1;
});
