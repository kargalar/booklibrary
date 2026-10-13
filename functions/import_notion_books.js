const fs = require('fs');
const dns = require('node:dns');
const path = require('path');
const assert = require('node:assert/strict');
const {initializeApp} = require('firebase-admin/app');
const {FieldValue, getFirestore, Timestamp} = require('firebase-admin/firestore');

const projectId = process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT || 'booklibrary-kargalar-2026';
dns.setDefaultResultOrder('ipv4first');
const readStatus = 'Okundu';
const readingStatus = 'Okunuyor';
const toReadStatus = 'Okunacak';
const batchSize = 350;
const hardcoverMinIntervalMs = 1100;
// ponytail: process-local rate limiter; use a shared limiter if imports run concurrently.
let hardcoverNextRequestAt = 0;

function argument(name) {
  const prefix = `${name}=`;
  const value = process.argv.find((item) => item.startsWith(prefix));
  return value ? value.slice(prefix.length) : null;
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let cell = '';
  let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const current = text[index];
    const next = text[index + 1];
    if (quoted) {
      if (current === '"' && next === '"') {
        cell += '"';
        index += 1;
      } else if (current === '"') {
        quoted = false;
      } else {
        cell += current;
      }
    } else if (current === '"') {
      quoted = true;
    } else if (current === ',') {
      row.push(cell);
      cell = '';
    } else if (current === '\n') {
      row.push(cell.replace(/\r$/, ''));
      rows.push(row);
      row = [];
      cell = '';
    } else {
      cell += current;
    }
  }
  if (cell || row.length) {
    row.push(cell);
    rows.push(row);
  }

  const headers = (rows.shift() || []).map((header) =>
    header.replace(/^\uFEFF/, '').trim());
  return rows
    .filter((values) => values.some((value) => value.trim()))
    .map((values) => Object.fromEntries(
      headers.map((header, index) => [header, values[index] || '']),
    ));
}

function normalizeText(value) {
  return String(value || '').replace(/\s+/g, ' ').trim();
}

function normalizeKey(value) {
  return normalizeText(value)
    .replace(/[\u00DD\u00D0]/g, 'I')
    .replace(/\u00C4\u00B1|\u00C4\u00B0/g, 'i')
    .replace(/\u00C4\u011E|\u00C4\u017E/g, 'g')
    .replace(/\u00C5\u017E|\u00C5\u00BE/g, 's')
    .replace(/\u00C3\u00BC/g, 'u')
    .replace(/\u00C3\u00B6/g, 'o')
    .replace(/\u00C3\u00A7/g, 'c')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase('tr-TR')
    .replace(/[\u0131\u0130]/g, 'i')
    .replace(/[\u011F\u011E]/g, 'g')
    .replace(/[\u015F\u015E]/g, 's')
    .replace(/[\u00FC\u00DC]/g, 'u')
    .replace(/[\u00F6\u00D6]/g, 'o')
    .replace(/[\u00E7\u00C7]/g, 'c')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function similarity(first, second) {
  if (!first || !second) return 0;
  if (first === second) return 1;
  const previous = Array.from({length: second.length + 1}, (_, index) => index);
  for (let row = 1; row <= first.length; row += 1) {
    let diagonal = previous[0];
    previous[0] = row;
    for (let column = 1; column <= second.length; column += 1) {
      const above = previous[column];
      previous[column] = first[row - 1] === second[column - 1]
        ? diagonal
        : 1 + Math.min(diagonal, above, previous[column - 1]);
      diagonal = above;
    }
  }
  return 1 - previous[second.length] / Math.max(first.length, second.length);
}

function mapStatus(value) {
  switch (normalizeText(value).toLowerCase()) {
    case 'read':
    case 'listened':
      return readStatus;
    case 'unfinished':
      return readingStatus;
    case 'to be read':
      return toReadStatus;
    default:
      return null;
  }
}

function parsePoint(value) {
  const point = Number.parseFloat(normalizeText(value).replace(',', '.'));
  return Number.isFinite(point) && point >= 1 && point <= 10 ? point : null;
}

function ratingFromPoint(value) {
  const point = parsePoint(value);
  return point == null ? null : Math.max(1, Math.min(5, Math.round(point / 2)));
}

function parseDate(value) {
  const parts = normalizeText(value).split(/→|->/);
  const date = new Date(parts.at(-1));
  return Number.isNaN(date.getTime()) ? null : date;
}

function rowQuality(row) {
  const status = normalizeText(row.status).toLowerCase();
  const statusScore = status === 'read' || status === 'listened'
    ? 3
    : status === 'unfinished' ? 2 : status === 'to be read' ? 1 : 0;
  return (parsePoint(row.point) == null ? 0 : 8) +
    (parseDate(row.date) == null ? 0 : 4) +
    (normalizeText(row.outhor) ? 2 : 0) + statusScore;
}

function chooseSourceRows(rows) {
  const unique = new Map();
  for (const row of rows) {
    const title = normalizeText(row.name);
    if (!title || normalizeKey(title) === 'puanlar') continue;
    const key = normalizeKey(title);
    const previous = unique.get(key);
    if (!previous || rowQuality(row) > rowQuality(previous) ||
        (rowQuality(row) === rowQuality(previous) &&
          (parseDate(row.date)?.getTime() || 0) > (parseDate(previous.date)?.getTime() || 0))) {
      unique.set(key, {...row, name: title, outhor: normalizeText(row.outhor)});
    }
  }
  return [...unique.values()];
}

const notionMetadata = /^(status|page\/duration|point|reaction|recommender|type|outhor|author|date)\s*:/i;
const markdownAttachment = /^\s*!?\[[^\]]*\]\(.*\)\s*$/;

function stripMarkdown(value) {
  return String(value || '')
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/(\*\*|__|~~|`)/g, '')
    .replace(/^\s*#{1,6}\s+/, '')
    .trim();
}

function textEntries(value) {
  if (Array.isArray(value)) {
    return value.filter((entry) => typeof entry === 'string' && entry.trim())
      .map((entry) => entry.trim());
  }
  return typeof value === 'string' && value.trim() ? [value.trim()] : [];
}

function mergeTextEntries(current, imported) {
  return [...new Set([...textEntries(current), ...textEntries(imported)])];
}

function sameTextEntries(first, second) {
  return first.length === second.length &&
    first.every((entry, index) => entry === second[index]);
}

function cleanMarkdownBlock(lines) {
  return lines.map((line) => stripMarkdown(line)).filter(Boolean).join('\n').trim();
}

function parseMarkdownNotes(text) {
  const lines = String(text || '').replace(/^\uFEFF/, '').replace(/\r/g, '').split('\n');
  const headingIndex = lines.findIndex((line) => /^#\s+/.test(line));
  if (headingIndex < 0) return null;

  const metadataIndex = lines.findIndex((line, index) =>
    index > headingIndex && notionMetadata.test(line));
  const titleLines = [lines[headingIndex].replace(/^#\s+/, '')];
  let titleEnd = headingIndex + 1;
  const titleContinuation = lines.slice(headingIndex + 1, metadataIndex)
    .filter((line, index, values) =>
      line.trim() || values.slice(index + 1).some((next) => next.trim()));
  if (metadataIndex > headingIndex &&
      titleContinuation.length && !titleContinuation.some((line) => !line.trim())) {
    while (titleEnd < metadataIndex && lines[titleEnd].trim()) {
      titleLines.push(lines[titleEnd]);
      titleEnd += 1;
    }
  }

  let bodyStart = titleEnd;
  while (bodyStart < lines.length &&
      (!lines[bodyStart].trim() || notionMetadata.test(lines[bodyStart]))) {
    bodyStart += 1;
  }

  const notes = [];
  const quotes = [];
  let noteLines = [];
  let quoteLines = [];
  const flushNote = () => {
    const note = cleanMarkdownBlock(noteLines);
    if (note) notes.push(note);
    noteLines = [];
  };
  const flushQuote = () => {
    const quote = cleanMarkdownBlock(quoteLines);
    if (quote) quotes.push(quote);
    quoteLines = [];
  };

  for (const rawLine of lines.slice(bodyStart)) {
    const line = rawLine.trimEnd();
    if (/^\s*>/.test(line)) {
      flushNote();
      const quoteLine = line.replace(/^\s*>\s?/, '').trim();
      if (quoteLine) quoteLines.push(quoteLine);
      continue;
    }
    if (!line.trim()) {
      flushNote();
      flushQuote();
      continue;
    }
    if (markdownAttachment.test(line) || notionMetadata.test(line) || /^\s*-{3,}\s*$/.test(line)) {
      flushNote();
      flushQuote();
      continue;
    }
    flushQuote();
    noteLines.push(line);
  }
  flushNote();
  flushQuote();

  return {
    title: stripMarkdown(titleLines.join(' ')),
    notes: mergeTextEntries([], notes),
    quotes: mergeTextEntries([], quotes),
  };
}

function readMarkdownNotes(exportDirectory) {
  const notesByTitle = new Map();
  for (const name of fs.readdirSync(exportDirectory).filter((file) => file.endsWith('.md'))) {
    const parsed = parseMarkdownNotes(
      fs.readFileSync(path.join(exportDirectory, name), 'utf8'),
    );
    if (!parsed?.title) continue;
    const key = normalizeKey(parsed.title);
    const previous = notesByTitle.get(key);
    notesByTitle.set(key, {
      title: parsed.title,
      notes: mergeTextEntries(previous?.notes, parsed.notes),
      quotes: mergeTextEntries(previous?.quotes, parsed.quotes),
    });
  }
  return [...notesByTitle.values()];
}

function authorKey(book) {
  if (typeof book.author === 'string') return normalizeKey(book.author);
  if (Array.isArray(book.authors)) return normalizeKey(book.authors.join(' '));
  return '';
}

function authorsMatch(source, book) {
  const sourceAuthor = normalizeKey(source.outhor);
  const existingAuthor = authorKey(book);
  if (!sourceAuthor || sourceAuthor === 'none' || !existingAuthor) return false;
  return sourceAuthor === existingAuthor || sourceAuthor.includes(existingAuthor) ||
    existingAuthor.includes(sourceAuthor) || similarity(sourceAuthor, existingAuthor) >= 0.85;
}

function findBook(source, books, ownerBookIds) {
  const sourceTitle = normalizeKey(source.name);
  const candidates = books
    .map((book) => ({
      book,
      titleScore: similarity(sourceTitle, normalizeKey(book.title)),
      authorMatch: authorsMatch(source, book),
      ownerMatch: ownerBookIds.has(book.id),
    }))
    .filter((candidate) => candidate.titleScore >= 0.9)
    .sort((first, second) =>
      (second.titleScore + (second.authorMatch ? 0.05 : 0) +
        (second.ownerMatch ? 0.02 : 0)) -
      (first.titleScore + (first.authorMatch ? 0.05 : 0) +
        (first.ownerMatch ? 0.02 : 0)));
  return candidates[0]?.book || null;
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

function metadataText(value) {
  if (typeof value === 'string') return normalizeText(value);
  if (typeof value === 'number') return Number.isFinite(value) ? `${value}` : '';
  if (!value || typeof value !== 'object' || Array.isArray(value)) return '';
  return metadataText(value.value || value.name || value.title || '');
}

function metadataTexts(value) {
  if (Array.isArray(value)) return value.flatMap((item) => metadataTexts(item));
  const text = metadataText(value);
  return text ? [text] : [];
}

function uniqueMetadataTexts(values, limit = 50) {
  return [...new Set(values.flatMap((value) => metadataTexts(value)))]
    .slice(0, limit);
}

function apiKey(value) {
  const key = metadataText(value);
  return key ? (key.startsWith('/') ? key : `/${key}`) : null;
}

function apiUrl(key) {
  return `https://openlibrary.org${apiKey(key)}.json`;
}

async function fetchJson(url) {
  try {
    const response = await fetch(url, {
      headers: {
        Accept: 'application/json',
        'User-Agent': 'booklibrary-notion-import/1.0',
      },
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) return null;
    return await response.json();
  } catch {
    return null;
  }
}

async function fetchGraphql(query, variables, token) {
  try {
    const response = await fetch('https://api.hardcover.app/v1/graphql', {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        'User-Agent': 'booklibrary-notion-import/1.0',
      },
      body: JSON.stringify({query, variables}),
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) return null;
    const payload = await response.json();
    return payload.errors?.length ? null : payload;
  } catch {
    return null;
  }
}

async function waitForHardcoverSlot() {
  const now = Date.now();
  const start = Math.max(now, hardcoverNextRequestAt);
  hardcoverNextRequestAt = start + hardcoverMinIntervalMs;
  if (start > now) {
    await new Promise((resolve) => setTimeout(resolve, start - now));
  }
}

async function mapWithConcurrency(items, limit, callback) {
  const results = [];
  let nextIndex = 0;
  const worker = async () => {
    while (nextIndex < items.length) {
      const index = nextIndex++;
      results[index] = await callback(items[index], index);
    }
  };
  await Promise.all(Array.from({length: Math.min(limit, items.length)}, worker));
  return results;
}

function authorMatches(expected, candidates) {
  const expectedKey = normalizeKey(expected);
  if (!expectedKey || expectedKey === 'none') return true;
  return candidates.some((candidate) => {
    const candidateKey = normalizeKey(candidate);
    return candidateKey === expectedKey || candidateKey.includes(expectedKey) ||
      expectedKey.includes(candidateKey) || similarity(expectedKey, candidateKey) >= 0.8;
  });
}

function firstValidIsbn(...values) {
  for (const value of values.flatMap((item) => metadataTexts(item))) {
    const isbn = normalizeIsbn(value);
    if (isbn) return isbn;
  }
  return null;
}

function lastPathPart(value) {
  const key = apiKey(value);
  return key ? key.split('/').at(-1) : null;
}

function languageLabel(code) {
  return {
    eng: 'İngilizce',
    tur: 'Türkçe',
    deu: 'Almanca',
    ger: 'Almanca',
    fra: 'Fransızca',
    fre: 'Fransızca',
    spa: 'İspanyolca',
    ita: 'İtalyanca',
    rus: 'Rusça',
    ara: 'Arapça',
  }[code] || null;
}

function openLibraryMetadataFields(source, document, edition, work, isbn) {
  const authors = uniqueMetadataTexts([
    document.author_name,
    edition?.authors,
  ], 8);
  const subjects = uniqueMetadataTexts([
    document.subject,
    work?.subjects,
    work?.genres,
  ]);
  const languageValues = uniqueMetadataTexts([
    edition?.languages,
    document.language,
  ], 8);
  const languageCode = languageValues
    .map((value) => value.split('/').at(-1).toLowerCase())
    .find((value) => value.length >= 2 && value.length <= 4) || null;
  const coverId = metadataText(edition?.covers?.[0]) ||
    metadataText(document.cover_i) || metadataText(work?.covers?.[0]);
  const editionKey = apiKey(edition?.key) ||
    apiKey(document.cover_edition_key) || apiKey(document.edition_key?.[0]);
  const workKey = apiKey(work?.key) || apiKey(document.key);
  const title = metadataText(edition?.title) || metadataText(document.title) || source.name;
  const author = authors.length ? authors.join(', ') : source.outhor;
  const pageCount = Number(
    edition?.number_of_pages || document.number_of_pages_median || work?.pages,
  );
  const isbnValues = [
    firstValidIsbn(edition?.isbn_13, document.isbn13, document.isbn),
    firstValidIsbn(edition?.isbn_10, document.isbn10, document.isbn),
  ].filter(Boolean);
  const fields = {
    recordType: 'book',
    title,
    author,
    authors: authors.length ? authors : (author ? [author] : []),
    titleSearch: normalizeKey(title),
    isbn: isbn || isbnValues[0] || null,
    isbnSearches: [...new Set([isbn, ...isbnValues].filter(Boolean))],
    metadataSource: isbn ? 'Open Library Search + ISBN' : 'Open Library Search',
    isbnApiData: edition || document,
    isbnApiEditionData: edition || {},
    isbnApiWorkData: work || {},
    metadataProviders: {
      openLibrarySearch: document,
      ...edition ? {openLibraryIsbn: edition} : {},
      ...work ? {openLibraryWork: work} : {},
    },
  };
  const optional = {
    subtitle: metadataText(edition?.subtitle) || metadataText(document.subtitle),
    description: metadataText(work?.description) || metadataText(edition?.description),
    pageCount: Number.isInteger(pageCount) && pageCount > 0 ? pageCount : null,
    subjects,
    tags: subjects,
    subjectPlaces: uniqueMetadataTexts([document.place, work?.subject_places]),
    subjectPeople: uniqueMetadataTexts([document.person, work?.subject_people]),
    subjectTimes: uniqueMetadataTexts([document.time, work?.subject_times]),
    publisher: metadataTexts(edition?.publishers)[0] || metadataTexts(document.publisher)[0],
    publishedDate: metadataTexts(edition?.publish_date)[0] ||
      metadataTexts(document.publish_date)[0] ||
      metadataText(document.first_publish_year),
    firstPublishDate: metadataText(work?.first_publish_date) ||
      metadataText(document.first_publish_year),
    languageCode,
    language: languageLabel(languageCode),
    coverUrl: coverId ? `https://covers.openlibrary.org/b/id/${coverId}-L.jpg?default=false` : null,
    isbn10: isbnValues.find((value) => value.length === 10) || null,
    isbn13: isbnValues.find((value) => value.length === 13) || null,
    editionId: lastPathPart(editionKey),
    workId: lastPathPart(workKey),
    sourceUrl: workKey ? `https://openlibrary.org${workKey}` :
      editionKey ? `https://openlibrary.org${editionKey}` : null,
  };
  for (const [key, value] of Object.entries(optional)) {
    if (value != null && value !== '' && (!Array.isArray(value) || value.length)) {
      fields[key] = value;
    }
  }
  return fields;
}

async function fetchOpenLibraryMetadata(source) {
  const url = new URL('https://openlibrary.org/search.json');
  url.searchParams.set('title', source.name);
  if (source.outhor) url.searchParams.set('author', source.outhor);
  url.searchParams.set('limit', '5');
  url.searchParams.set('fields', [
    'title', 'subtitle', 'author_name', 'number_of_pages_median', 'subject',
    'publisher', 'publish_date', 'first_publish_year', 'language', 'isbn',
    'isbn10', 'isbn13', 'cover_i', 'cover_edition_key', 'edition_key',
    'key', 'place', 'person', 'time',
  ].join(','));
  const payload = await fetchJson(url);
  const documents = Array.isArray(payload?.docs) ? payload.docs : [];
  const sourceTitle = normalizeKey(source.name);
  const sourceAuthor = normalizeKey(source.outhor) === 'none'
    ? ''
    : normalizeKey(source.outhor);
  const candidates = documents.map((document) => {
    const titleScore = similarity(sourceTitle, normalizeKey(document.title));
    const authors = metadataTexts(document.author_name);
    const authorMatch = authorMatches(source.outhor, authors);
    return {document, titleScore, authorMatch, score: titleScore + (authorMatch ? 0.08 : 0)};
  }).sort((first, second) => second.score - first.score);
  const best = candidates[0];
  if (!best || best.titleScore < 0.75 ||
      (sourceAuthor && !best.authorMatch && best.titleScore < 0.95)) return null;

  const isbn = firstValidIsbn(best.document.isbn13, best.document.isbn10, best.document.isbn);
  const editionKey = best.document.cover_edition_key || best.document.edition_key?.[0];
  const edition = isbn
    ? await fetchJson(`https://openlibrary.org/isbn/${isbn}.json`)
    : editionKey ? await fetchJson(apiUrl(editionKey)) : null;
  const workKey = apiKey(edition?.works?.[0]?.key) || apiKey(best.document.key);
  const work = workKey ? await fetchJson(apiUrl(workKey)) : null;
  return openLibraryMetadataFields(source, best.document, edition, work, isbn);
}

function googleBooksMetadataFields(source, volume) {
  const info = volume.volumeInfo || {};
  const authors = uniqueMetadataTexts(info.authors, 8);
  const identifiers = (info.industryIdentifiers || [])
    .map((item) => normalizeIsbn(item?.identifier))
    .filter(Boolean);
  const title = metadataText(info.title) || source.name;
  const author = authors.length ? authors.join(', ') : source.outhor;
  const description = metadataText(info.description)
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  const coverUrl = metadataText(
    info.imageLinks?.extraLarge || info.imageLinks?.large ||
      info.imageLinks?.medium || info.imageLinks?.thumbnail,
  ).replace(/^http:/, 'https:');
  const languageCode = metadataText(info.language).toLowerCase() || null;
  const fields = {
    recordType: 'book',
    title,
    author,
    authors: authors.length ? authors : (author ? [author] : []),
    titleSearch: normalizeKey(title),
    isbn: identifiers[0] || null,
    isbnSearches: identifiers,
    metadataSource: 'Google Books',
    isbnApiData: volume,
    isbnApiEditionData: info,
    isbnApiWorkData: {},
    metadataProviders: {googleBooks: volume},
  };
  const optional = {
    subtitle: metadataText(info.subtitle),
    description,
    pageCount: Number.isInteger(info.pageCount) && info.pageCount > 0
      ? info.pageCount
      : null,
    subjects: uniqueMetadataTexts(info.categories),
    tags: uniqueMetadataTexts(info.categories),
    publisher: metadataText(info.publisher),
    publishedDate: metadataText(info.publishedDate),
    firstPublishDate: metadataText(info.publishedDate),
    languageCode,
    language: languageLabel(languageCode),
    coverUrl,
    isbn10: identifiers.find((value) => value.length === 10) || null,
    isbn13: identifiers.find((value) => value.length === 13) || null,
    editionId: metadataText(volume.id),
    sourceUrl: metadataText(info.infoLink) ||
      (volume.id ? `https://books.google.com/books?id=${volume.id}` : null),
  };
  for (const [key, value] of Object.entries(optional)) {
    if (value != null && value !== '' && (!Array.isArray(value) || value.length)) {
      fields[key] = value;
    }
  }
  return fields;
}

async function fetchGoogleBooksMetadata(source) {
  const url = new URL('https://www.googleapis.com/books/v1/volumes');
  const author = normalizeKey(source.outhor) === 'none' ? '' : source.outhor;
  url.searchParams.set('q', [source.name, author].filter(Boolean).join(' '));
  url.searchParams.set('maxResults', '5');
  url.searchParams.set('printType', 'books');
  const payload = await fetchJson(url);
  const candidates = (Array.isArray(payload?.items) ? payload.items : [])
    .map((volume) => {
      const info = volume.volumeInfo || {};
      const titleScore = similarity(normalizeKey(source.name), normalizeKey(info.title));
      const authorMatch = authorMatches(source.outhor, info.authors || []);
      return {volume, titleScore, authorMatch, score: titleScore + (authorMatch ? 0.08 : 0)};
    })
    .sort((first, second) => second.score - first.score);
  const best = candidates[0];
  const sourceAuthor = normalizeKey(source.outhor) === 'none'
    ? ''
    : normalizeKey(source.outhor);
  if (!best || best.titleScore < 0.75 ||
      (sourceAuthor && !best.authorMatch && best.titleScore < 0.95)) return null;
  return googleBooksMetadataFields(source, best.volume);
}

function hardcoverMetadataFields(source, document) {
  const authors = uniqueMetadataTexts([
    document.author_names,
    document.contributions?.map((item) => item.author?.name),
  ], 8);
  const isbnValues = uniqueMetadataTexts(document.isbns)
    .map((value) => normalizeIsbn(value))
    .filter(Boolean);
  const title = metadataText(document.title) || source.name;
  const author = authors.length ? authors.join(', ') : source.outhor;
  const coverUrl = metadataText(document.image?.url);
  const bookId = metadataText(document.id);
  const fields = {
    recordType: 'book',
    title,
    author,
    authors: authors.length ? authors : (author ? [author] : []),
    titleSearch: normalizeKey(title),
    isbn: isbnValues[0] || null,
    isbnSearches: isbnValues,
    metadataSource: 'Hardcover',
    isbnApiData: document,
    isbnApiEditionData: document,
    isbnApiWorkData: document,
    metadataProviders: {hardcover: document},
  };
  const optional = {
    subtitle: metadataText(document.subtitle),
    description: metadataText(document.description),
    pageCount: Number.isInteger(document.pages) && document.pages > 0
      ? document.pages
      : null,
    subjects: uniqueMetadataTexts([document.genres, document.tags]),
    tags: uniqueMetadataTexts(document.tags),
    publishedDate: metadataText(document.release_date) ||
      metadataText(document.release_year),
    firstPublishDate: metadataText(document.release_date) ||
      metadataText(document.release_year),
    coverUrl,
    isbn10: isbnValues.find((value) => value.length === 10) || null,
    isbn13: isbnValues.find((value) => value.length === 13) || null,
    workId: bookId,
    sourceUrl: document.slug
      ? `https://hardcover.app/books/${document.slug}`
      : bookId ? `https://hardcover.app/book/${bookId}` : null,
  };
  for (const [key, value] of Object.entries(optional)) {
    if (value != null && value !== '' && (!Array.isArray(value) || value.length)) {
      fields[key] = value;
    }
  }
  return fields;
}

async function fetchHardcoverMetadata(source) {
  const token = normalizeText(process.env.HARDCOVER_API_TOKEN);
  if (!token) return null;
  await waitForHardcoverSlot();
  const query = `
query SearchBooks($query: String!) {
  search(query: $query, query_type: "Book", per_page: 5, page: 1) {
    results
  }
}`;
  const author = normalizeKey(source.outhor) === 'none' ? '' : source.outhor;
  const payload = await fetchGraphql(query, {
    query: [source.name, author].filter(Boolean).join(' '),
  }, token);
  const hits = payload?.data?.search?.results?.hits;
  const candidates = (Array.isArray(hits) ? hits : [])
    .map((hit) => {
      const document = hit.document || {};
      const titles = [document.title, ...metadataTexts(document.alternative_titles)];
      const titleScore = Math.max(...titles.map((title) =>
        similarity(normalizeKey(source.name), normalizeKey(title))), 0);
      const authorMatch = authorMatches(source.outhor, [
        ...metadataTexts(document.author_names),
        ...metadataTexts(document.contributions?.map((item) => item.author?.name)),
      ]);
      return {document, titleScore, authorMatch, score: titleScore + (authorMatch ? 0.08 : 0)};
    })
    .sort((first, second) => second.score - first.score);
  const best = candidates[0];
  const sourceAuthor = normalizeKey(source.outhor) === 'none'
    ? ''
    : normalizeKey(source.outhor);
  if (!best || best.titleScore < 0.75 ||
      (sourceAuthor && !best.authorMatch && best.titleScore < 0.95)) return null;
  return hardcoverMetadataFields(source, best.document);
}

async function fetchBookMetadata(source) {
  return await fetchOpenLibraryMetadata(source) ||
    await fetchHardcoverMetadata(source) || fetchGoogleBooksMetadata(source);
}

function canonicalId(title, author) {
  return `book_title_${encodeURIComponent(normalizeKey(title))}_` +
    encodeURIComponent(normalizeKey(author));
}

function relationId(ownerId, bookId) {
  return `notion_${encodeURIComponent(ownerId)}_${encodeURIComponent(bookId)}`;
}

function ownerCounts(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  return Object.fromEntries(Object.entries(value)
    .filter(([, count]) => Number.isFinite(Number(count)))
    .map(([owner, count]) => [owner, Number(count)]));
}

function asInt(value) {
  return Number.isFinite(Number(value)) ? Number(value) : 0;
}

function canonicalForNewBook(source) {
  const author = normalizeText(source.outhor);
  return {
    recordType: 'book',
    title: source.name,
    author,
    authors: author ? [author] : [],
    titleSearch: normalizeKey(source.name),
    isbnSearches: [],
    libraryCount: 0,
    libraryOwnerCounts: {},
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function relationFields(source, isNew) {
  const status = mapStatus(source.status);
  const fields = {
    status,
    updatedAt: FieldValue.serverTimestamp(),
  };
  const completedAt = parseDate(source.date);
  if (status === readStatus && completedAt) {
    fields.completedAt = Timestamp.fromDate(completedAt);
  } else if (status !== readStatus) {
    fields.completedAt = null;
  }
  if (isNew) {
    fields.wishlist = false;
    fields.inHomeLibrary = false;
    fields.createdAt = FieldValue.serverTimestamp();
  }
  return fields;
}

function findExportDirectory(explicit) {
  if (explicit) return path.resolve(explicit);
  const root = path.resolve(__dirname, '..');
  const directory = fs.readdirSync(root, {withFileTypes: true})
    .find((entry) => entry.isDirectory() && entry.name.includes('_ExportBlock'));
  if (!directory) throw new Error('Notion export klasörü bulunamadı.');
  return path.join(root, directory.name);
}

async function commitOperations(operations) {
  for (let start = 0; start < operations.length; start += batchSize) {
    const batch = db.batch();
    for (const operation of operations.slice(start, start + batchSize)) {
      batch.set(operation.reference, operation.data, {merge: true});
    }
    await batch.commit();
  }
}

async function buildPlan(ownerId, exportDirectory, {enrichMetadata = false} = {}) {
  const csv = fs.readdirSync(exportDirectory)
    .find((name) => name.endsWith('_all.csv'));
  if (!csv) throw new Error(`${exportDirectory} içinde *_all.csv bulunamadı.`);

  const [bookSnapshot, relationSnapshot, profileSnapshot] = await Promise.all([
    db.collection('books').get(),
    db.collection('libraryBooks').get(),
    db.collection('users').doc(ownerId).get(),
  ]);
  const allBooks = new Map(bookSnapshot.docs.map((document) => [
    document.id,
    {id: document.id, ...document.data()},
  ]));
  const ownerRelations = new Map();
  const ownerBookIds = new Set();
  for (const document of relationSnapshot.docs) {
    const data = document.data();
    if (data.libraryId === ownerId && typeof data.bookId === 'string') {
      ownerRelations.set(data.bookId, {id: document.id, ...data});
      ownerBookIds.add(data.bookId);
    }
  }

  const rows = chooseSourceRows(parseCsv(
    fs.readFileSync(path.join(exportDirectory, csv), 'utf8'),
  ));
  const canonicalWrites = new Map();
  const relationWrites = new Map();
  const ratingWrites = new Map();
  const matches = [];
  const noteStats = {
    files: 0,
    booksWithContent: 0,
    matchedBooks: 0,
    unmatchedBooks: 0,
    notes: 0,
    quotes: 0,
    updates: 0,
    unmatchedTitles: [],
  };
  const metadataStats = {
    requested: 0,
    enriched: 0,
    notFound: 0,
    failed: 0,
    providers: {},
  };
  const metadataRequests = [];
  const writeCanonical = (bookId, data) => {
    const previous = canonicalWrites.get(bookId);
    canonicalWrites.set(bookId, {
      reference: db.collection('books').doc(bookId),
      data: {...(previous?.data || {}), ...data},
    });
  };
  const writeRelation = (reference, data) => {
    const previous = relationWrites.get(reference.path);
    relationWrites.set(reference.path, {
      reference,
      data: {...(previous?.data || {}), ...data},
    });
  };

  for (const source of rows) {
    let book = findBook(source, [...allBooks.values()], ownerBookIds);
    const isExistingBook = book != null;
    if (!book) {
      const id = canonicalId(source.name, source.outhor);
      book = {id, ...canonicalForNewBook(source)};
      allBooks.set(id, book);
    }

    const existingRelation = ownerRelations.get(book.id);
    const isNewRelation = !existingRelation;
    const relationReference = existingRelation
      ? db.collection('libraryBooks').doc(existingRelation.id)
      : db.collection('libraryBooks').doc(relationId(ownerId, book.id));
    if (isNewRelation) {
      ownerRelations.set(book.id, {
        id: relationReference.id,
        libraryId: ownerId,
        bookId: book.id,
      });
      ownerBookIds.add(book.id);
      const counts = ownerCounts(book.libraryOwnerCounts);
      counts[ownerId] = (counts[ownerId] || 0) + 1;
      book.libraryOwnerCounts = counts;
      book.libraryCount = asInt(book.libraryCount) + 1;
      writeCanonical(book.id, {
        ...(isExistingBook ? {} : canonicalForNewBook(source)),
        libraryCount: book.libraryCount,
        libraryOwnerCounts: counts,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    if (enrichMetadata && relationReference.id.startsWith('notion_') &&
        !normalizeText(book.metadataSource)) {
      metadataRequests.push({book, source});
    }

    if (isExistingBook && !normalizeText(book.author) && normalizeText(source.outhor)) {
      writeCanonical(book.id, {
        author: source.outhor,
        authors: [source.outhor],
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    writeRelation(relationReference, {
      ...(isNewRelation ? {libraryId: ownerId, bookId: book.id} : {}),
      ...relationFields(source, isNewRelation),
    });

    const rating = ratingFromPoint(source.point);
    if (rating != null) {
      const ratingReference = relationReference.collection('ratings').doc(ownerId);
      const profile = profileSnapshot.data() || {};
      ratingWrites.set(ratingReference.path, {
        reference: ratingReference,
        data: {
          userId: ownerId,
          username: profile.username || '',
          userName: profile.username ? `@${profile.username}` : 'Okur',
          value: rating,
          source: 'notion',
          updatedAt: FieldValue.serverTimestamp(),
        },
      });
    }
    matches.push({
      source: source.name,
      existing: isExistingBook,
      status: mapStatus(source.status),
      rating,
    });
  }

  metadataStats.requested = metadataRequests.length;
  await mapWithConcurrency(metadataRequests, 4, async ({book, source}) => {
    try {
      const metadata = await fetchBookMetadata(source);
      if (!metadata) {
        metadataStats.notFound += 1;
        return;
      }
      const sourceTitle = normalizeText(book.title) || metadata.title;
      const sourceAuthor = normalizeText(book.author) || metadata.author;
      const canonicalMetadata = {
        ...metadata,
        title: sourceTitle,
        author: sourceAuthor,
        authors: normalizeText(book.author)
          ? (Array.isArray(book.authors) && book.authors.length
                ? book.authors
                : [sourceAuthor])
          : metadata.authors,
        titleSearch: normalizeKey(sourceTitle),
      };
      allBooks.set(book.id, {...book, ...canonicalMetadata});
      writeCanonical(book.id, canonicalMetadata);
      metadataStats.enriched += 1;
      const provider = canonicalMetadata.metadataSource || 'Bilinmiyor';
      metadataStats.providers[provider] = (metadataStats.providers[provider] || 0) + 1;
    } catch {
      metadataStats.failed += 1;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  });

  const markdownNotes = readMarkdownNotes(exportDirectory);
  noteStats.files = fs.readdirSync(exportDirectory)
    .filter((name) => name.endsWith('.md')).length;
  for (const markdownNote of markdownNotes) {
    if (normalizeKey(markdownNote.title) === 'puanlar') continue;
    if (!markdownNote.notes.length && !markdownNote.quotes.length) continue;
    noteStats.booksWithContent += 1;
    noteStats.notes += markdownNote.notes.length;
    noteStats.quotes += markdownNote.quotes.length;

    const book = findBook({name: markdownNote.title, outhor: ''},
      [...allBooks.values()], ownerBookIds);
    const relation = book ? ownerRelations.get(book.id) : null;
    if (!book || !relation) {
      noteStats.unmatchedBooks += 1;
      noteStats.unmatchedTitles.push(markdownNote.title);
      continue;
    }
    noteStats.matchedBooks += 1;

    const nextNotes = mergeTextEntries(relation.notes, markdownNote.notes);
    const nextQuotes = mergeTextEntries(relation.quotes, markdownNote.quotes);
    const relationData = {};
    if (!sameTextEntries(textEntries(relation.notes), nextNotes)) {
      relationData.notes = nextNotes;
    }
    if (!sameTextEntries(textEntries(relation.quotes), nextQuotes)) {
      relationData.quotes = nextQuotes;
    }
    if (Object.keys(relationData).length) {
      writeRelation(db.collection('libraryBooks').doc(relation.id), {
        ...relationData,
        updatedAt: FieldValue.serverTimestamp(),
      });
      noteStats.updates += 1;
    }
  }

  return {
    rows,
    matches,
    noteStats,
    metadataStats,
    operations: [
      ...canonicalWrites.values(),
      ...relationWrites.values(),
      ...ratingWrites.values(),
    ],
    references: [
      ...canonicalWrites.values(),
      ...relationWrites.values(),
      ...ratingWrites.values(),
    ].map((operation) => operation.reference),
  };
}

async function main() {
  const ownerId = argument('--owner') || process.env.NOTION_OWNER_ID;
  if (!ownerId) throw new Error('--owner=UID zorunludur.');
  const exportDirectory = findExportDirectory(argument('--export-dir'));
  initializeApp({projectId});
  db = getFirestore();
  const enrichMetadata = process.argv.includes('--enrich-metadata') ||
    process.argv.includes('--commit');
  const plan = await buildPlan(ownerId, exportDirectory, {enrichMetadata});
  const existing = plan.matches.filter((match) => match.existing).length;
  const ratings = plan.matches.filter((match) => match.rating != null).length;
  const statusUpdates = plan.matches.length;
  console.log(JSON.stringify({
    dryRun: !process.argv.includes('--commit'),
    exportDirectory,
    sourceRows: plan.rows.length,
    existingBooks: existing,
    newBooks: plan.matches.length - existing,
    statusUpdates,
    ratings,
    notionNotes: plan.noteStats,
    metadata: plan.metadataStats,
    firestoreWrites: plan.operations.length,
    sampleNewBooks: plan.matches.filter((match) => !match.existing)
      .slice(0, 20).map((match) => match.source),
  }, null, 2));

  if (!process.argv.includes('--commit')) return;
  await commitOperations(plan.operations);
  const verification = await db.getAll(...plan.references);
  const missing = verification.filter((snapshot) => !snapshot.exists);
  if (missing.length) {
    throw new Error(`Aktarım doğrulaması başarısız: ${missing.map((snapshot) => snapshot.ref.path).join(', ')}`);
  }
  console.log('Notion aktarımı tamamlandı ve doğrulandı.');
}

function selfTest() {
  const rows = parseCsv('name,outhor,point,status\n"A, B",Author,7.8,read\n');
  assert.equal(rows[0].name, 'A, B');
  assert.equal(mapStatus('listened'), readStatus);
  assert.equal(mapStatus('unfinished'), readingStatus);
  assert.equal(mapStatus(''), null);
  assert.equal(ratingFromPoint('7.8'), 4);
  assert.equal(ratingFromPoint('9.5'), 5);
  assert.equal(parseDate('June 3, 2022 → June 20, 2022').getFullYear(), 2022);
  const markdown = parseMarkdownNotes(
    '# Kitap\n\nstatus: read\n\n![](cover.png)\n[file (x).pdf](file_(x).pdf)\n> Alıntı\n> devam\n\nNot **burada**.\n',
  );
  assert.deepEqual(markdown.notes, ['Not burada.']);
  assert.deepEqual(markdown.quotes, ['Alıntı\ndevam']);
  console.log('Notion import self-test passed.');
}

let db;
if (process.argv.includes('--self-test')) selfTest();
else main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
