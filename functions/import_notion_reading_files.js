const fs = require('fs');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const path = require('path');
const {initializeApp} = require('firebase-admin/app');
const {FieldValue, getFirestore} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');

const projectId = process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT || 'booklibrary-kargalar-2026';
const bucketName = 'booklibrary-kargalar-2026.firebasestorage.app';
const formats = ['pdf', 'epub'];

function argument(name) {
  const prefix = `${name}=`;
  const value = process.argv.find((item) => item.startsWith(prefix));
  return value ? value.slice(prefix.length) : null;
}

function normalizeKey(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase('tr-TR')
    .replace(/[ıİ]/g, 'i')
    .replace(/[ğĞ]/g, 'g')
    .replace(/[şŞ]/g, 's')
    .replace(/[üÜ]/g, 'u')
    .replace(/[öÖ]/g, 'o')
    .replace(/[çÇ]/g, 'c')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function fileKey(name) {
  return normalizeKey(path.parse(name).name.replace(/^\d{3,4}[-_]/, ''))
    .replace(/\bpdfdrive\b/g, ' ')
    .replace(/\b(?:copy|kopya)\b/g, ' ')
    .replace(/\b\d{2,4}s\b/g, ' ')
    .replace(/q/g, 'k')
    .replace(/x/g, 'h')
    .replace(/\s+/g, ' ')
    .trim();
}

function tokenScore(expected, actual) {
  const expectedTokens = normalizeKey(expected).split(' ').filter(Boolean);
  const actualTokens = normalizeKey(actual).split(' ').filter(Boolean);
  if (!expectedTokens.length || !actualTokens.length) return 0;
  let actualIndex = 0;
  let matched = 0;
  for (const token of expectedTokens) {
    const index = actualTokens.findIndex((candidate, candidateIndex) =>
      candidateIndex >= actualIndex && candidate === token);
    if (index >= 0) {
      matched += 1;
      actualIndex = index + 1;
    }
  }
  return matched / expectedTokens.length;
}

const filenameAliases = [
  [['alice', 'xariqalar'], 'Alice Harikalar Diyarında'],
  [['sivil', 'itaetsizlik'], 'Sivil İtaatsizlik'],
  [['genlerle', 'babaa'], 'Gençlerle Başbaşa'],
  [['alk', 'knut', 'hamsun'], 'Açlık'],
  [['anton', 'ehov', 'altnc'], 'Altıncı Koğuş'],
  [['dam', 'mahkmunun', 'son', 'gn'], 'Bir İdam Mahkumunun Son Günü'],
  [['carlos', 'maria', 'dominguez', 'kat', 'ev'], 'Kağıt Ev'],
  [['george', 'orwell', '1984'], '1984'],
  [['fareler', 'nsanlar'], 'Fareler Ve İnsanlar'],
  [['halil', 'cibran', 'ermi'], 'Ermiş'],
  [['imizdeki', 'eytan', 'sabahattin'], 'İçimizdeki Şeytan'],
  [['benjamin', 'buttonn', 'tuhaf', 'hikayesi'], 'Benjamin Button`un Tuhaf Hikayesi'],
  [['kr', 'bayku', 'sdk'], 'Kör Baykuş'],
  [['lber', 'ortayl', 'bir', 'mr'], 'Bir Ömür Nasıl Yaşanır'],
  [['nsanlar', 'uyurlar', 'lnce', 'uyanrlar'], 'İnsanlar Uykudadır Ölünce Uyanırlar'],
  [['olaanst', 'bir', 'gece'], 'Olağanüstü Bir Gece'],
  [['tolstoy', 'tiraflarm'], 'İtiraflarım'],
  [['vahetin', 'ars', 'jack', 'london'], 'Vahşetin Çağrısı'],
  [['yzbann', 'kz', 'aleksandr', 'pukin'], 'Yüzbaşının Kızı'],
  [['mart', 'jonathan', 'livingston', 'richard', 'bach'], 'Martı Jonathan Livingson'],
  [['reat', 'nuri', 'gntkin', 'yaprak', 'dkm'], 'Yaprak Dökümü'],
  [['reat', 'nuri', 'yaprak', 'dkm'], 'Yaprak Dökümü'],
  [['beyaz', 'zambaklar', 'lkesinde'], 'Beyaz Zambaklar Ülkesinde'],
  [['farabi', 'var', 'msn', 'ki', 'yok'], 'Var Mısın Ki Yok Olmaktan Korkuyorsun'],
  [['deghirmendir', 'bu', 'dunya'], 'Bir Değirmendir Bu Dünya'],
  [['ustaliq', 'gerekdiren', 'qafaya', 'takmama'], 'Ustalık Gerektiren Kafaya Takmama Sanatı'],
  [['bir', 'bilim', 'adamnn', 'rom'], 'Bir Bilim Adamının Romanı'],
  [['krlk', 'jos', 'saramago'], 'Körlük'],
  [['topya', 'thomas', 'more'], 'Ütopya'],
  [['yabanc', 'albert', 'camus'], 'Yabancı'],
  [['zn', 'z'], 'Sergüzeşt'],
];

function aliasTitle(fileName) {
  const rawKey = normalizeKey(path.parse(fileName).name.replace(/^\d{3,4}[-_]/, ''))
    .replace(/\bpdfdrive\b/g, ' ')
    .replace(/\b(?:copy|kopya)\b/g, ' ')
    .replace(/\b\d{2,4}s\b/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  const keys = [rawKey, fileKey(fileName)];
  const alias = filenameAliases.find(([tokens]) =>
    tokens.every((token) => keys.some((key) => key.includes(token))));
  return alias ? alias[1] : null;
}

function fileMatchScore(file, book) {
  const key = fileKey(file.name);
  const alias = aliasTitle(file.name);
  const title = normalizeKey(alias || book.title);
  const author = normalizeKey(book.author);
  const titleScore = alias
    ? normalizeKey(book.title) === title ? 1 : 0
    : key.split(' ').includes(title) || key.includes(` ${title} `) ||
      key.startsWith(`${title} `) || key.endsWith(` ${title}`)
    ? 1
    : tokenScore(title, key);
  const authorScore = author ? tokenScore(author, key) : 0;
  return {titleScore, score: titleScore + authorScore * 0.2};
}

function findBook(file, books) {
  const candidates = books.map((book) => ({
    book,
    ...fileMatchScore(file, book),
  }))
    .filter((candidate) => candidate.titleScore >= 0.75)
    .sort((first, second) => second.score - first.score);
  return candidates[0] || null;
}

function findExportDirectory(explicit) {
  if (explicit) return path.resolve(explicit);
  const root = path.resolve(__dirname, '..');
  const directory = fs.readdirSync(root, {withFileTypes: true})
    .find((entry) => entry.isDirectory() && entry.name.includes('_ExportBlock'));
  if (!directory) throw new Error('Notion export klasörü bulunamadı.');
  return path.join(root, directory.name);
}

function filesIn(directory) {
  return fs.readdirSync(directory, {withFileTypes: true})
    .filter((entry) => entry.isFile() && formats.includes(
      path.extname(entry.name).slice(1).toLowerCase(),
    ))
    .map((entry) => {
      const fullPath = path.join(directory, entry.name);
      const extension = path.extname(entry.name).slice(1).toLowerCase();
      const bytes = fs.readFileSync(fullPath);
      return {
        name: entry.name,
        path: fullPath,
        extension,
        size: bytes.length,
        hash: crypto.createHash('sha256').update(bytes).digest('hex'),
      };
    });
}

function contentType(format) {
  return format === 'pdf' ? 'application/pdf' : 'application/epub+zip';
}

function shellArgument(value) {
  const text = String(value);
  return /[\s"&|<>^]/.test(text) ? `"${text.replace(/"/g, '\\"')}"` : text;
}

function gcloudCommand(args) {
  const command = process.platform === 'win32' ? 'gcloud.cmd' : 'gcloud';
  const result = spawnSync(command, args.map(shellArgument), {
    encoding: 'utf8',
    stdio: 'inherit',
    shell: process.platform === 'win32',
  });
  if (result.status !== 0) {
    throw new Error(result.stderr?.trim() || `gcloud failed (${result.status})`);
  }
  return result.stdout || '';
}

function gcloudMetadata(uri) {
  const command = process.platform === 'win32' ? 'gcloud.cmd' : 'gcloud';
  const result = spawnSync(command, [
    'storage', 'objects', 'describe', uri, '--format=json',
  ], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    shell: process.platform === 'win32',
  });
  if (result.status !== 0) return null;
  return JSON.parse(result.stdout);
}

function metadataMatches(metadata, file) {
  return Number(metadata.size) === file.size &&
    (metadata.metadata?.sha256 || metadata.custom_fields?.sha256) === file.hash;
}

async function main() {
  const ownerId = argument('--owner');
  if (!ownerId) throw new Error('--owner=UID zorunludur.');
  const exportDirectory = findExportDirectory(argument('--export-dir'));
  initializeApp({projectId, storageBucket: bucketName});
  const db = getFirestore();
  const bucket = getStorage().bucket(bucketName);
  const useGcloud = process.argv.includes('--gcloud');
  const [relationSnapshot, bookSnapshot] = await Promise.all([
    db.collection('libraryBooks').where('libraryId', '==', ownerId).get(),
    db.collection('books').get(),
  ]);
  const books = bookSnapshot.docs.map((document) => ({
    id: document.id,
    ...document.data(),
  }));
  const booksById = new Map(books.map((book) => [book.id, book]));
  const relations = relationSnapshot.docs.map((document) => ({
    id: document.id,
    data: document.data(),
    book: booksById.get(document.data().bookId),
  })).filter((entry) => entry.book);
  const files = filesIn(exportDirectory);
  const hashKeys = new Set();
  const matched = [];
  const unmatched = [];
  let duplicateFiles = 0;
  for (const file of files) {
    const match = findBook(file, relations.map((entry) => entry.book));
    if (!match) {
      unmatched.push(file.name);
      continue;
    }
    const relation = relations.find((entry) => entry.book.id === match.book.id);
    const hashKey = `${match.book.id}:${file.extension}:${file.hash}`;
    if (hashKeys.has(hashKey)) {
      duplicateFiles += 1;
      continue;
    }
    hashKeys.add(hashKey);
    matched.push({...file, relation, match});
  }

  const selected = new Map();
  const conflicts = [];
  for (const file of matched.sort((first, second) => second.size - first.size)) {
    const key = `${file.relation.id}:${file.extension}`;
    if (selected.has(key)) {
      conflicts.push(file.name);
      continue;
    }
    selected.set(key, file);
  }

  const summary = {
    dryRun: process.argv.includes('--dry-run'),
    exportDirectory,
    files: files.length,
    matched: selected.size,
    unmatched,
    duplicateFiles,
    conflicts,
    uploaded: 0,
    alreadyPresent: 0,
    skippedConflicts: 0,
  };
  if (summary.dryRun) {
    console.log(JSON.stringify({
      ...summary,
      matches: [...selected.values()].map((file) => ({
        file: file.name,
        format: file.extension,
        title: file.relation.book.title,
        author: file.relation.book.author || '',
        score: file.match.score,
      })),
    }, null, 2));
    return;
  }

  const uploaded = [];
  const relationFormats = new Map();
  try {
    for (const file of selected.values()) {
      const objectName = `books/${ownerId}/${file.relation.id}/reading.${file.extension}`;
      const remote = bucket.file(objectName);
      const uri = `gs://${bucketName}/${objectName}`;
      if (useGcloud) {
        const metadata = gcloudMetadata(uri);
        if (metadata) {
          if (metadataMatches(metadata, file)) {
            summary.alreadyPresent += 1;
          } else {
            summary.skippedConflicts += 1;
            conflicts.push(file.name);
            continue;
          }
        } else {
          gcloudCommand([
            'storage', 'cp', file.path, uri,
            `--content-type=${contentType(file.extension)}`,
            `--custom-metadata=sha256=${file.hash},sourceFile=${file.name}`,
            '--quiet',
          ]);
          const metadataAfterUpload = gcloudMetadata(uri);
          if (!metadataAfterUpload || !metadataMatches(metadataAfterUpload, file)) {
            throw new Error(`Dosya doğrulaması başarısız: ${file.name}`);
          }
          uploaded.push(() => {
            try {
              gcloudCommand(['storage', 'rm', uri, '--quiet']);
            } catch (_) {
              // Keep the original error if cleanup is unavailable.
            }
          });
          summary.uploaded += 1;
        }
      } else {
        const [existing] = await remote.exists();
        if (existing) {
          const [metadata] = await remote.getMetadata();
          if (metadataMatches(metadata, file)) {
            summary.alreadyPresent += 1;
          } else {
            summary.skippedConflicts += 1;
            conflicts.push(file.name);
            continue;
          }
        } else {
          await remote.save(fs.readFileSync(file.path), {
            resumable: false,
            metadata: {
              contentType: contentType(file.extension),
              metadata: {
                sha256: file.hash,
                sourceFile: file.name,
              },
            },
          });
          const [metadata] = await remote.getMetadata();
          if (!metadataMatches(metadata, file)) {
            throw new Error(`Dosya doğrulaması başarısız: ${file.name}`);
          }
          uploaded.push(() => remote.delete().catch(() => {}));
          summary.uploaded += 1;
        }
      }
      const entry = relationFormats.get(file.relation.id) || new Set();
      entry.add(file.extension);
      relationFormats.set(file.relation.id, entry);
    }

    const batch = db.batch();
    for (const [relationId, formatSet] of relationFormats) {
      const relation = relationSnapshot.docs.find((document) => document.id === relationId);
      const currentFormat = relation?.data().readingFormat;
      const available = formats.filter((format) => formatSet.has(format));
      batch.set(db.collection('libraryBooks').doc(relationId), {
        readingFormat: formats.includes(currentFormat) && available.includes(currentFormat)
          ? currentFormat
          : available[0],
        readingFormats: available,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    await batch.commit();
  } catch (error) {
    await Promise.all(uploaded.map((cleanup) => cleanup()));
    throw error;
  }

  const verification = await Promise.all([...selected.values()].map(async (file) => {
    const objectName = `books/${ownerId}/${file.relation.id}/reading.${file.extension}`;
    const uri = `gs://${bucketName}/${objectName}`;
    const metadata = useGcloud
      ? gcloudMetadata(uri)
      : (await bucket.file(objectName).getMetadata())[0];
    return metadata != null && metadataMatches(metadata, file);
  }));
  if (verification.some((value) => !value)) {
    throw new Error('Yüklenen dosyaların doğrulaması başarısız.');
  }
  console.log(JSON.stringify(summary, null, 2));
  console.log('Notion okuma dosyaları aktarıldı ve doğrulandı.');
}

main().catch((error) => {
  console.error(error.stack || error.message || error);
  process.exitCode = 1;
});
