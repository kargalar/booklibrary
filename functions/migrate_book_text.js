const {Firestore} = require('@google-cloud/firestore');

const projectId = 'booklibrary-kargalar-2026';
const textFields = [
  'title',
  'author',
  'publisher',
  'tags',
  'subjectPlaces',
  'subjectPeople',
  'subjectTimes',
  'contributions',
];
const listFields = ['subjects', ...textFields.slice(3)];
const repairs = [
  ['\u00c3\u0087', 'Ç'],
  ['\u00c3\u0096', 'Ö'],
  ['\u00c4\u00b0', 'İ'],
  ['\u00c4\u017e', 'Ğ'],
  ['\u00c5\u017e', 'Ş'],
  ['\u00c3\u009c', 'Ü'],
  ['\u00c3\u00a7', 'ç'],
  ['\u00c3\u00b6', 'ö'],
  ['\u00c4\u00b1', 'ı'],
  ['\u00c4\u009f', 'ğ'],
  ['\u00c5\u009f', 'ş'],
  ['\u00c3\u00bc', 'ü'],
  ['\u00c3', ''],
  ['\u00c2', ''],
  ['\u00e2\u0080\u0099', '’'],
  ['\u00e2\u0080\u009c', '"'],
  ['\u00e2\u0080\u009d', '"'],
  ['\u00e2\u0080\u0093', '-'],
  ['\u00e2\u0080\u0094', '-'],
  ['\u00e2\u0080\u00a6', '...'],
  ['I\u0307', 'İ'],
  ['i\u0307', 'i'],
  ['S\u0327', 'Ş'],
  ['s\u0327', 'ş'],
  ['G\u0308', 'Ğ'],
  ['g\u0308', 'ğ'],
  ['U\u0308', 'Ü'],
  ['u\u0308', 'ü'],
  ['O\u0308', 'Ö'],
  ['o\u0308', 'ö'],
  ['C\u0327', 'Ç'],
  ['c\u0327', 'ç'],
];

function normalizeText(value) {
  let normalized = String(value).normalize('NFC');
  for (const [from, to] of repairs) normalized = normalized.split(from).join(to);
  return normalized
    .replace(/[\u00a0\u2007\u202f]/g, ' ')
    .replaceAll('\uFFFD', '')
    .replace(/\s+/g, ' ')
    .trim();
}

function key(value) {
  return normalizeText(value)
    .toLocaleLowerCase('tr-TR')
    .replaceAll('ı', 'i')
    .replace(/[íìîï]/g, 'i')
    .replaceAll('ğ', 'g')
    .replaceAll('ş', 's')
    .replaceAll('ü', 'u')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

const publisherAliases = new Map([
  ['can yayinlari', 'Can Yayınları'],
  ['can yaynlar', 'Can Yayınları'],
  ['can yay nlar', 'Can Yayınları'],
  ['yapi kredi yayinlari', 'Yapı Kredi Yayınları'],
  ['yap kredi yaynlar', 'Yapı Kredi Yayınları'],
  ['is bankasi kultur yayinlari', 'İş Bankası Kültür Yayınları'],
  ['bankas kltr yaynlar', 'İş Bankası Kültür Yayınları'],
  ['turkiye is bankasi kultur yayinlari', 'Türkiye İş Bankası Kültür Yayınları'],
  ['is bankasi', 'İş Bankası'],
  ['bankas', 'İş Bankası'],
  ['iletisim yayinlari', 'İletişim Yayınları'],
  ['ithaki yayinlari', 'İthaki Yayınları'],
  ['dogan kitap', 'Doğan Kitap'],
  ['koridor yayincilik', 'Koridor Yayıncılık'],
  ['metis yayincilik', 'Metis Yayıncılık'],
  ['everest yayinlari', 'Everest Yayınları'],
  ['dergah yaynlar', 'Dergah Yayınları'],
  ['dergah yayinlari', 'Dergah Yayınları'],
  ['dergah', 'Dergah Yayınları'],
  ['dogan yayinlari', 'Doğan Yayınları'],
  ['doru bati yayinlari', 'Doğu Batı Yayınları'],
  ['dogu bati yayinlari', 'Doğu Batı Yayınları'],
  ['beyan yayincilik', 'Beyan Yayıncılık'],
  ['sel yayincilik', 'Sel Yayıncılık'],
  ['panama yayincilik', 'Panama Yayıncılık'],
  ['say yayinlari', 'Say Yayınları'],
  ['kirmizi kedi yayinevi', 'Kırmızı Kedi Yayınevi'],
  ['altinpost', 'AltınPost'],
  ['altin kitaplar yayinevi', 'Altın Kitaplar Yayınevi'],
  ['puslu yayincilik', 'Puslu Yayıncılık'],
  ['yagmur yayinevi suleyman ozdemir', 'Yağmur Yayınevi - Süleyman Özdemir'],
  ['timas yayinlari', 'Timaş Yayınları'],
  ['ksurat yaynlar', 'Küsurat Yayınları'],
  ['ayrinti', 'Ayrıntı'],
  ['inkilap ve kitabevi', 'İnkılâp ve Kitabevi'],
  ['iletisim yayinevi', 'İletişim Yayınları'],
  ['iletisim yayincilik', 'İletişim Yayınları'],
  ['pegasus yayinlari', 'Pegasus Yayınları'],
  ['final kultur sanat yayinlari', 'Final Kültür Sanat Yayınları'],
  ['domingo yayinevi', 'Domingo Yayınevi'],
  ['brand april yayincilik', 'Brand: April Yayıncılık'],
]);

const authorAliases = new Map([
  ['mustafa kutlu', 'Mustafa Kutlu'],
  ['tarik tufan', 'Tarık Tufan'],
  ['resat nuri guntekin', 'Reşat Nuri Güntekin'],
  ['oguz atay', 'Oğuz Atay'],
  ['cemil meric', 'Cemil Meriç'],
  ['cahit zarifoglu', 'Cahit Zarifoğlu'],
  ['selcuk baran', 'Selçuk Baran'],
  ['huseyin rahmi gurpinar', 'Hüseyin Rahmi Gürpınar'],
  ['yusuf atilgan', 'Yusuf Atılgan'],
  ['ayse kulin', 'Ayşe Kulin'],
]);

const genreAliases = [
  ['autobiograph', 'Otobiyografi'],
  ['otobiyografi', 'Otobiyografi'],
  ['memoir', 'Otobiyografi'],
  ['biograph', 'Biyografi'],
  ['biyografi', 'Biyografi'],
  ['science fiction', 'Bilim kurgu'],
  ['sci fi', 'Bilim kurgu'],
  ['fiction', 'Roman'],
  ['novel', 'Roman'],
  ['roman', 'Roman'],
  ['essay', 'Deneme'],
  ['deneme', 'Deneme'],
  ['poetry', 'Şiir'],
  ['poem', 'Şiir'],
  ['verse', 'Şiir'],
  ['siir', 'Şiir'],
  ['philosoph', 'Felsefe'],
  ['felsefe', 'Felsefe'],
  ['short stor', 'Öykü'],
  ['story', 'Öykü'],
  ['oyku', 'Öykü'],
  ['hikaye', 'Öykü'],
  ['drama', 'Tiyatro'],
  ['theater', 'Tiyatro'],
  ['theatre', 'Tiyatro'],
  ['tiyatro', 'Tiyatro'],
  ['mystery', 'Polisiye'],
  ['detective', 'Polisiye'],
  ['crime', 'Polisiye'],
  ['polisiye', 'Polisiye'],
  ['fantasy', 'Fantastik'],
  ['fantastik', 'Fantastik'],
  ['history', 'Tarih'],
  ['tarih', 'Tarih'],
  ['psycholog', 'Psikoloji'],
  ['psikoloji', 'Psikoloji'],
  ['children', 'Çocuk'],
  ['childrens', 'Çocuk'],
  ['cocuk', 'Çocuk'],
];

function canonicalGenre(value) {
  const normalized = key(value);
  return genreAliases.find(([alias]) =>
    normalized === alias || normalized.includes(alias),
  )?.[1] ?? normalizeText(value);
}

function splitAuthors(value) {
  return String(value)
    .split(/[,;]/)
    .map(normalizeText)
    .filter(Boolean);
}

function addVariant(variants, field, value) {
  const normalized = normalizeText(value);
  const normalizedKey = key(normalized);
  if (!normalized || !normalizedKey) return;
  const fieldVariants = variants.get(field) ?? new Map();
  const current = fieldVariants.get(normalizedKey) ?? {value: normalized, count: 0};
  current.count++;
  if (displayScore(normalized) > displayScore(current.value)) current.value = normalized;
  fieldVariants.set(normalizedKey, current);
  variants.set(field, fieldVariants);
}

function displayScore(value) {
  const TurkishLetters = value.match(/[çğıöşüÇĞİÖŞÜ]/g)?.length ?? 0;
  const damaged = value.match(/[?\uFFFD]/g)?.length ?? 0;
  const allCaps = value === value.toUpperCase() && value !== value.toLowerCase();
  return TurkishLetters * 4 - damaged * 20 - (allCaps ? 1 : 0);
}

function chooseVariant(variants, field, value) {
  const normalized = normalizeText(value);
  const normalizedKey = key(normalized);
  if (!normalizedKey) return normalized;
  if (field === 'publisher' && publisherAliases.has(normalizedKey)) {
    return publisherAliases.get(normalizedKey);
  }
  if (field === 'author' && authorAliases.has(normalizedKey)) {
    return authorAliases.get(normalizedKey);
  }
  return variants.get(field)?.get(normalizedKey)?.value ?? normalized;
}

function normalizeList(variants, field, value) {
  const labels = new Map();
  for (const item of Array.isArray(value) ? value : []) {
    const label = field === 'subjects'
      ? canonicalGenre(item)
      : chooseVariant(variants, field, item);
    if (label && !labels.has(key(label))) labels.set(key(label), label);
  }
  return [...labels.values()];
}

function normalizeDocument(variants, original, collection) {
  const data = {...original};
  const updates = {};
  if (typeof data.title === 'string') {
    data.title = chooseVariant(variants, 'title', data.title);
    if (data.title !== original.title) updates.title = data.title;
  }

  const authorNames = [
    ...splitAuthors(typeof data.author === 'string' ? data.author : ''),
    ...(Array.isArray(data.authors) ? data.authors.filter((value) => typeof value === 'string') : []),
  ];
  const normalizedAuthors = [];
  const seenAuthors = new Set();
  for (const name of authorNames) {
    const normalized = chooseVariant(variants, 'author', name);
    if (normalized && !seenAuthors.has(key(normalized))) {
      seenAuthors.add(key(normalized));
      normalizedAuthors.push(normalized);
    }
  }
  if (typeof data.author === 'string') {
    data.author = normalizedAuthors.join(', ');
    if (data.author !== original.author) updates.author = data.author;
  }
  if (normalizedAuthors.length && JSON.stringify(normalizedAuthors) !== JSON.stringify(original.authors)) {
    updates.authors = normalizedAuthors;
  }
  if (typeof data.publisher === 'string') {
    data.publisher = chooseVariant(variants, 'publisher', data.publisher);
    if (data.publisher !== original.publisher) updates.publisher = data.publisher;
  }
  for (const field of listFields) {
    if (!Array.isArray(data[field])) continue;
    data[field] = normalizeList(variants, field, data[field]);
    if (JSON.stringify(data[field]) !== JSON.stringify(original[field])) updates[field] = data[field];
  }
  if (collection === 'catalogBooks' && typeof data.title === 'string') {
    const titleSearch = key(data.title);
    if (data.titleSearch !== titleSearch) updates.titleSearch = titleSearch;
  }
  return updates;
}

async function main() {
  const dryRun = process.argv.includes('--dry-run');
  const db = new Firestore({projectId});
  const collections = ['books', 'catalogBooks'];
  const snapshots = await Promise.all(collections.map((name) => db.collection(name).get()));
  const variants = new Map();
  for (let i = 0; i < snapshots.length; i++) {
    for (const document of snapshots[i].docs) {
      const data = document.data();
      if (typeof data.title === 'string') addVariant(variants, 'title', data.title);
      if (typeof data.publisher === 'string') addVariant(variants, 'publisher', data.publisher);
      for (const name of splitAuthors(typeof data.author === 'string' ? data.author : '')) {
        addVariant(variants, 'author', name);
      }
      for (const name of Array.isArray(data.authors) ? data.authors : []) {
        if (typeof name === 'string') addVariant(variants, 'author', name);
      }
      for (const field of listFields) {
        for (const value of Array.isArray(data[field]) ? data[field] : []) {
          if (typeof value === 'string') addVariant(variants, field, value);
        }
      }
    }
  }

  let changed = 0;
  let fieldChanges = 0;
  const batches = [];
  let batch = db.batch();
  let batchSize = 0;
  for (let i = 0; i < snapshots.length; i++) {
    for (const document of snapshots[i].docs) {
      const updates = normalizeDocument(variants, document.data(), collections[i]);
      const fields = Object.keys(updates);
      if (!fields.length) continue;
      changed++;
      fieldChanges += fields.length;
      if (changed <= 20) console.log(collections[i], document.id, fields.join(', '));
      if (!dryRun) {
        batch.update(document.ref, updates);
        batchSize++;
        if (batchSize === 400) {
          batches.push(batch.commit());
          batch = db.batch();
          batchSize = 0;
        }
      }
    }
  }
  if (!dryRun && batchSize) batches.push(batch.commit());
  if (!dryRun) await Promise.all(batches);
  console.log(JSON.stringify({dryRun, changedDocuments: changed, changedFields: fieldChanges}));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
