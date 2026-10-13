const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { onRequest } = require('firebase-functions/v2/https');

initializeApp();

exports.lookupHardcover = onRequest(
  { region: 'europe-west1', preserveExternalChanges: true },
  async (req, res) => {
    if (req.method !== 'POST') {
      return res.status(405).json({ message: 'Only POST requests are supported.' });
    }

    const authorization = req.get('authorization') ?? '';
    const idToken = authorization.replace(/^Bearer\s+/i, '').trim();
    if (!idToken) {
      return res.status(401).json({ message: 'You must sign in first.' });
    }

    try {
      await getAuth().verifyIdToken(idToken);
    } catch {
      return res.status(401).json({ message: 'The Firebase session is invalid.' });
    }

    const isbn = normalizeIsbn(req.body?.isbn);
    if (!isbn) {
      return res.status(400).json({ message: 'Enter a valid ISBN.' });
    }

    let hardcoverResponse;
    try {
      hardcoverResponse = await fetch('https://api.hardcover.app/v1/graphql', {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          Authorization: `Bearer ${process.env.HARDCOVER_API_TOKEN}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          query: `
query HardcoverEditionByIsbn($isbn: String!) {
  editions(
    where: {
      _or: [
        { isbn_10: { _eq: $isbn } }
        { isbn_13: { _eq: $isbn } }
      ]
    }
    limit: 1
  ) {
    id
    title
    subtitle
    isbn_10
    isbn_13
    edition_format
    pages
    release_date
    language { language }
    image { url }
    publisher { name }
    book {
      id
      title
      subtitle
      description
      pages
      slug
      image { url }
      contributions { author { name } }
    }
  }
}`,
          variables: { isbn },
        }),
      });
    } catch {
      return res.status(502).json({ message: 'Could not connect to Hardcover.' });
    }

    const payload = await hardcoverResponse.json().catch(() => null);
    if (!hardcoverResponse.ok || !payload) {
      return res.status(502).json({ message: 'Hardcover did not respond.' });
    }
    if (Array.isArray(payload.errors) && payload.errors.length > 0) {
      return res.status(502).json({ message: 'Could not retrieve book details from Hardcover.' });
    }

    const edition = payload.data?.editions?.[0];
    return edition
      ? res.status(200).json(edition)
      : res.status(404).json({ message: 'This ISBN was not found on Hardcover.' });
  },
);

function normalizeIsbn(value) {
  const isbn = String(value ?? '').toUpperCase().replace(/[^0-9X]/g, '');
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
