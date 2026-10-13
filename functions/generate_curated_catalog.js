const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const output = resolvePath(argumentValue('--output') ||
  path.join(__dirname, 'reports', 'turkish-curated-500.jsonl'));
const limit = positiveInteger('--limit') || 500;
const detailConcurrency = positiveInteger('--concurrency') || 8;

const drSources = [
  {
    label: 'D&R En Çok Satan 500 Kitap',
    url: 'https://www.dr.com.tr/kataloglar_/encoksatan500kitap/3505',
    maxPages: 8,
  },
  {
    label: 'D&R Can Yayınları kitapları',
    url: 'https://www.dr.com.tr/sectiklerimiz/kitap?Manufacturer=Can%20Yay%C4%B1nlar%C4%B1',
    maxPages: 8,
  },
  {
    label: 'D&R Hasan Âli Yücel Klasikleri',
    url: 'https://www.dr.com.tr/kataloglar_/hasanaliyucel/3949',
    maxPages: 13,
  },
  {
    label: 'D&R En Çok Satan Romanlar',
    url: 'https://www.dr.com.tr/kataloglar_/encoksatanromanlar/3733',
    maxPages: 8,
  },
];

const openLibrarySources = [
  {
    label: 'Open Library — Türkçe popüler kitaplar',
    params: {q: 'language:tur', sort: 'editions', offset: 0},
  },
  {
    label: 'Open Library — Türkçe melankoli kitapları',
    params: {q: 'language:tur subject:melancholy', sort: 'editions'},
  },
  {
    label: 'Open Library — Türkçe klasik kitaplar',
    params: {q: 'language:tur subject:classics', sort: 'editions'},
  },
  {
    label: 'Open Library — Türkçe edebiyat kitapları',
    params: {q: 'language:tur subject:literature', sort: 'editions'},
  },
];

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
        (total, digit, index) => total +
          (digit === 'X' ? 10 : Number(digit)) * (10 - index),
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

function decodeHtml(value) {
  return text(value)
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&nbsp;/g, ' ')
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
    .replace(/&#x([\da-f]+);/gi, (_, code) => String.fromCodePoint(parseInt(code, 16)));
}

function key(value) {
  return decodeHtml(value).toLocaleLowerCase('tr-TR').normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/ı/g, 'i')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function attribute(html, name) {
  const match = html.match(new RegExp(
    `${name}\\s*=\\s*([\\\'\"])([\\s\\S]*?)\\1`,
    'i',
  ));
  return match ? decodeHtml(match[2]) : '';
}

async function fetchText(url) {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await fetch(url, {
        headers: {
          Accept: 'text/html,application/json',
          'User-Agent': 'BookLibrary Turkish curated catalog import',
        },
        signal: AbortSignal.timeout(30_000),
      });
      if (!response.ok) {
        throw new Error(`${new URL(url).hostname} yanıtı: ${response.status}`);
      }
      return response.text();
    } catch (error) {
      lastError = error;
      if (attempt < 3) await new Promise((resolve) => setTimeout(resolve, attempt * 1000));
    }
  }
  throw lastError;
}

function productCards(html) {
  const starts = [...html.matchAll(/<div class="product-card\b[^>]*>/gi)]
    .map((match) => match.index);
  return starts.map((start, index) =>
    html.slice(start, starts[index + 1] ?? html.length));
}

function productFromCard(card, source) {
  if (key(attribute(card, 'data-prd-lang')) !== 'turkce') return null;
  const href = attribute(card, 'data-category') ||
    card.match(/<a[^>]+href=['"]([^'"]*\/urunno=[^'"]*)['"]/i)?.[1] || '';
  if (!href) return null;
  let item = {};
  try {
    item = JSON.parse(attribute(card, 'data-gtm'));
  } catch (_) {}
  const title = firstText(item.item_name)
    .replace(/\s+-\s+Hasan Ali Yücel Klasikleri.*$/i, '');
  const author = firstText(item.author);
  if (!title || !author) return null;
  return {
    source: source.label,
    sourceUrl: source.url,
    href: new URL(href, source.url).toString(),
    title,
    author,
    publisher: firstText(item.publisher),
    rank: Number(attribute(card, 'data-position')) || Number(item.index) || null,
  };
}

async function collectDrProducts() {
  const products = [];
  const seen = new Set();
  for (const source of drSources) {
    for (let page = 1; page <= source.maxPages; page += 1) {
      const pageUrl = new URL(source.url);
      pageUrl.searchParams.set('Page', String(page));
      let html;
      try {
        html = await fetchText(pageUrl.toString());
      } catch (error) {
        if (error.message.includes('404') || error.message.includes('410')) break;
        throw error;
      }
      const cards = productCards(html);
      if (!cards.length) break;
      for (const card of cards) {
        const product = productFromCard(card, source);
        if (!product || seen.has(product.href)) continue;
        seen.add(product.href);
        products.push(product);
      }
      console.log(`[D&R] ${source.label} sayfa=${page} aday=${products.length}`);
    }
  }
  return products;
}

function productDetails(html, product) {
  const isbns = [...html.matchAll(/(?:gtin13|data-flix-ean|isbn)"?\s*[:=]\s*["']?(97[89]\d{10}|\d{9}[\dX])["']?/gi)]
    .map((match) => normalizeIsbn(match[1]))
    .filter(Boolean);
  const isbn13 = isbns.find((isbn) => isbn.length === 13) || '';
  const isbn10 = isbns.find((isbn) => isbn.length === 10) || '';
  return {
    ...product,
    isbn: isbn13 || isbn10,
    isbn13: isbn13 || null,
    isbn10: isbn10 || null,
    language: 'Türkçe',
    publication_date: firstText(product.publication_date),
    pages: null,
    format: null,
    description: null,
    cover_url: null,
  };
}

async function enrichDrProducts(products) {
  const rows = [];
  for (let index = 0; index < products.length; index += detailConcurrency) {
    const batch = products.slice(index, index + detailConcurrency);
    const results = await Promise.all(batch.map(async (product) => {
      try {
        const html = await fetchText(product.href);
        return productDetails(html, product);
      } catch (error) {
        console.warn(`[D&R] ayrıntı alınamadı: ${product.href} (${error.message})`);
        return null;
      }
    }));
    rows.push(...results.filter(Boolean));
    console.log(`[D&R] ISBN zenginleştirme=${Math.min(index + detailConcurrency, products.length)}/${products.length}`);
  }
  return rows;
}

function firstTurkishEdition(work) {
  const editions = Array.isArray(work.editions?.docs) ? work.editions.docs : [];
  return editions.find((edition) =>
    Array.isArray(edition.language) && edition.language.includes('tur'),
  ) || null;
}

function openLibraryRow(work, source, rank) {
  const edition = firstTurkishEdition(work);
  if (!edition) return null;
  const isbns = (Array.isArray(edition.isbn) ? edition.isbn : [])
    .map(normalizeIsbn)
    .filter(Boolean);
  const isbn13 = isbns.find((isbn) => isbn.length === 13) || '';
  const isbn10 = isbns.find((isbn) => isbn.length === 10) || '';
  const title = firstText(edition.title, work.title);
  const author = firstText(work.author_name);
  if (!title || !author) return null;
  const editionKey = firstText(edition.key);
  const coverId = Number(edition.covers?.[0] || work.cover_i);
  return {
    source: source.label,
    sourceUrl: `https://openlibrary.org/search.json?${new URLSearchParams(source.params)}`,
    href: editionKey ? `https://openlibrary.org${editionKey}` : `https://openlibrary.org${work.key}`,
    title,
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
    cover_url: Number.isInteger(coverId) && coverId > 0
      ? `https://covers.openlibrary.org/b/id/${coverId}-L.jpg?default=false`
      : null,
    rank,
  };
}

async function collectOpenLibraryRows() {
  const rows = [];
  for (const source of openLibrarySources) {
    const url = new URL('https://openlibrary.org/search.json');
    for (const [name, value] of Object.entries(source.params)) {
      url.searchParams.set(name, String(value));
    }
    url.searchParams.set('limit', '1000');
    url.searchParams.set('fields', fields);
    const response = await fetchText(url.toString());
    const payload = JSON.parse(response);
    for (const work of payload.docs || []) {
      const row = openLibraryRow(work, source, rows.length + 1);
      if (row) rows.push(row);
    }
    console.log(`[Open Library] ${source.label} aday=${rows.length}`);
  }
  return rows;
}

function identity(row) {
  return row.isbn13 || row.isbn10 || `${key(row.title)}|${key(row.author)}`;
}

function mergeRows(rows) {
  const merged = new Map();
  for (const row of rows) {
    const id = identity(row);
    const existing = merged.get(id);
    if (!existing) {
      merged.set(id, row);
      continue;
    }
    existing.source = `${existing.source} · ${row.source}`;
    if (!existing.isbn && row.isbn) Object.assign(existing, row);
  }
  return [...merged.values()].slice(0, limit).map((row, index) => ({
    book_url: row.href,
    title: row.title,
    rank: index + 1,
    source_lists: [row.source],
    author: row.author,
    isbn: row.isbn || null,
    isbn13: row.isbn13,
    isbn10: row.isbn10,
    publisher: row.publisher || null,
    publication_date: row.publication_date || null,
    pages: row.pages,
    language: 'Türkçe',
    format: row.format,
    description: row.description,
    cover_url: row.cover_url,
  }));
}

function curatedOrder(drRows, openLibraryRows) {
  const take = (label, count) =>
    drRows.filter((row) => row.source === label).slice(0, count);
  const selected = [
    ...take('D&R En Çok Satan 500 Kitap', 220),
    ...take('D&R Hasan Âli Yücel Klasikleri', 120),
    ...take('D&R Can Yayınları kitapları', 60),
    ...take('D&R En Çok Satan Romanlar', 40),
  ];
  const selectedUrls = new Set(selected.map((row) => row.href));
  return [
    ...selected,
    ...openLibraryRows,
    ...drRows.filter((row) => !selectedUrls.has(row.href)),
  ];
}

async function main() {
  const drCandidates = curatedOrder(await collectDrProducts(), []).slice(
    0,
    Math.max(limit, 50),
  );
  const drRows = await enrichDrProducts(drCandidates);
  const openLibraryRows = await collectOpenLibraryRows();
  const rows = mergeRows(curatedOrder(drRows, openLibraryRows));
  if (rows.length < limit) {
    throw new Error(`Yalnızca ${rows.length} benzersiz Türkçe kitap bulundu; ${limit} gerekiyor.`);
  }
  fs.mkdirSync(path.dirname(output), {recursive: true});
  fs.writeFileSync(output, `${rows.map((row) => JSON.stringify(row)).join('\n')}\n`, 'utf8');
  console.log(JSON.stringify({written: rows.length, output}, null, 2));
}

main().catch((error) => {
  console.error(error.stack || error.message || error);
  process.exitCode = 1;
});
