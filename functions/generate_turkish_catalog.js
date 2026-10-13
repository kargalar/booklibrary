const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const defaultOutput = path.join(
  __dirname,
  'reports',
  'openlibrary-turkish-popular-1000.jsonl',
);
const limit = positiveInteger('--limit') || 1000;
const output = resolvePath(argumentValue('--output') || defaultOutput);
const fields = [
  'key',
  'title',
  'author_name',
  'first_publish_year',
  'cover_i',
  'editions',
  'editions.key',
  'editions.title',
  'editions.language',
  'editions.isbn',
  'editions.publish_date',
  'editions.number_of_pages',
  'editions.publishers',
  'editions.covers',
].join(',');

function argumentValue(prefix) {
  const value = process.argv.find((item) => item.startsWith(`${prefix}=`));
  return value?.slice(prefix.length + 1) || '';
}

function positiveInteger(prefix) {
  const value = Number(argumentValue(prefix));
  return Number.isInteger(value) && value > 0 ? value : null;
}

function resolvePath(value) {
  return path.isAbsolute(value) ? value : path.resolve(root, value);
}

function text(value) {
  return String(value ?? '').normalize('NFC').replace(/\s+/g, ' ').trim();
}

function firstText(...values) {
  for (const value of values.flat()) {
    const candidate = text(value);
    if (candidate && candidate.toLowerCase() !== 'none') return candidate;
  }
  return '';
}

function normalizeIsbn(value) {
  const isbn = text(value).toUpperCase().replace(/[^0-9X]/g, '');
  if (isbn.length === 10) {
    const valid = [...isbn].every((digit) => /[0-9X]/.test(digit)) &&
      [...isbn].reduce(
        (total, digit, index) => total + (digit === 'X' ? 10 : Number(digit)) * (10 - index),
        0,
      ) % 11 === 0;
    return valid ? isbn : '';
  }
  if (isbn.length === 13 && [...isbn].every((digit) => /[0-9]/.test(digit))) {
    const valid = [...isbn].reduce(
      (total, digit, index) => total + Number(digit) * (index % 2 ? 3 : 1),
      0,
    ) % 10 === 0;
    return valid ? isbn : '';
  }
  return '';
}

function firstEdition(work) {
  const editions = Array.isArray(work.editions?.docs) ? work.editions.docs : [];
  return editions.find((edition) =>
    Array.isArray(edition.language) && edition.language.includes('tur'),
  ) || null;
}

function sourceRow(work, rank) {
  const edition = firstEdition(work);
  if (!edition) return null;

  const isbns = (Array.isArray(edition.isbn) ? edition.isbn : [])
    .map(normalizeIsbn)
    .filter(Boolean);
  const isbn13 = isbns.find((isbn) => isbn.length === 13) || '';
  const isbn10 = isbns.find((isbn) => isbn.length === 10) || '';
  const editionKey = firstText(edition.key);
  const coverId = Number(edition.covers?.[0] || work.cover_i);
  const author = firstText(work.author_name);
  const title = firstText(edition.title, work.title);
  if (!title || !author) return null;

  return {
    book_url: editionKey ? `https://openlibrary.org${editionKey}` : `https://openlibrary.org${work.key}`,
    title,
    rank,
    source_lists: ['Open Library Türkçe baskılar — baskı sayısına göre'],
    author,
    isbn: isbn13 || isbn10,
    isbn13: isbn13 || null,
    isbn10: isbn10 || null,
    publisher: firstText(edition.publishers),
    publication_date: firstText(edition.publish_date, work.first_publish_year),
    pages: Number.isInteger(edition.number_of_pages) ? edition.number_of_pages : null,
    language: 'Türkçe',
    format: null,
    description: null,
    cover_url: Number.isInteger(coverId) && coverId > 0 ?
      `https://covers.openlibrary.org/b/id/${coverId}-L.jpg?default=false` : null,
  };
}

async function fetchCatalog() {
  const url = new URL('https://openlibrary.org/search.json');
  url.searchParams.set('q', 'language:tur');
  url.searchParams.set('sort', 'editions');
  url.searchParams.set('lang', 'tr');
  url.searchParams.set('limit', String(limit));
  url.searchParams.set('fields', fields);
  const response = await fetch(url, {
    headers: {
      Accept: 'application/json',
      'User-Agent': 'BookLibrary Turkish catalog import',
    },
    signal: AbortSignal.timeout(120_000),
  });
  if (!response.ok) throw new Error(`Open Library yanıtı: ${response.status}`);
  return response.json();
}

async function main() {
  const payload = await fetchCatalog();
  const rows = [];
  const seen = new Set();
  for (const work of payload.docs || []) {
    const row = sourceRow(work, rows.length + 1);
    if (!row) continue;
    const identity = row.isbn13 || row.isbn10 || `${row.title}|${row.author}`.toLocaleLowerCase('tr-TR');
    if (seen.has(identity)) continue;
    seen.add(identity);
    rows.push(row);
    if (rows.length >= limit) break;
  }

  fs.mkdirSync(path.dirname(output), {recursive: true});
  fs.writeFileSync(output, `${rows.map((row) => JSON.stringify(row)).join('\n')}\n`, 'utf8');
  console.log(JSON.stringify({found: payload.numFound || 0, written: rows.length, output}, null, 2));
}

main().catch((error) => {
  console.error(error.stack || error.message || error);
  process.exitCode = 1;
});
