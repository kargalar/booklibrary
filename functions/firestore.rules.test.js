const {before, after, beforeEach, test} = require('node:test');
const {readFileSync} = require('node:fs');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {
  collection, deleteDoc, doc, getDoc, getDocs, query, setDoc, updateDoc, where,
  writeBatch,
} = require('firebase/firestore');

let env;
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-booklibrary-check', firestore: {
    host: '127.0.0.1',
    port: Number(process.env.FIRESTORE_EMULATOR_HOST?.split(':').pop() ?? 8080),
    rules: readFileSync(require('node:path').join(__dirname, '../firestore.rules'), 'utf8'),
  }});
});
after(async () => env?.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'friendLinks/alice_bob'), {
      memberIds: ['alice', 'bob'],
      permissions: {alice: 'read', bob: 'read'},
    });
    await setDoc(doc(db, 'users/alice'), {displayName: 'Alice'});
    await setDoc(doc(db, 'users/bob'), {displayName: 'Bob'});
    await setDoc(doc(db, 'users/eve'), {displayName: 'Eve'});
    await setDoc(doc(db, 'books/book'), {
      recordType: 'book',
      title: 'Kitap',
      author: 'Yazar',
      libraryCount: 2,
      libraryOwnerCounts: {alice: 1, bob: 1},
    });
    await setDoc(doc(db, 'libraryBooks/alice-copy'), {
      libraryId: 'alice', bookId: 'book', status: 'Okundu', wishlist: false,
    });
    await setDoc(doc(db, 'libraryBooks/bob-copy'), {
      libraryId: 'bob', bookId: 'book', status: 'Okunuyor', wishlist: false,
    });
  });
});
const dbFor = (uid) => env.authenticatedContext(uid).firestore();
const adminDb = () => env.authenticatedContext('database-admin', {
  email: 'm.islam0422@gmail.com', email_verified: true,
}).firestore();

test('database admin can manage all Firestore documents', async () => {
  const db = adminDb();
  await assertSucceeds(getDoc(doc(db, 'libraryBooks/alice-copy')));
  await assertSucceeds(setDoc(doc(db, 'users/admin-check'), {role: 'admin'}));
  await assertSucceeds(deleteDoc(doc(db, 'users/admin-check')));
});

test('user profiles are readable only by their owner and accepted friends', async () => {
  await assertSucceeds(getDoc(doc(dbFor('alice'), 'users/alice')));
  await assertSucceeds(getDoc(doc(dbFor('alice'), 'users/bob')));
  await assertFails(getDoc(doc(dbFor('alice'), 'users/eve')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'users/alice')));
});

test('only the new relation schema is writable', async () => {
  await assertFails(setDoc(doc(dbFor('alice'), 'books/legacy'), {
    ownerId: 'alice', title: 'Eski kayıt', author: 'Yazar', status: 'Okundu',
  }));
  await assertFails(setDoc(doc(dbFor('alice'), 'catalogBooks/book'), {
    title: 'Katalog', author: 'Yazar',
  }));
  await assertFails(setDoc(doc(dbFor('alice'), 'libraryBooks/invalid'), {
    libraryId: 'alice', bookId: 'missing', status: 'Okunacak',
  }));
  await assertSucceeds(getDoc(doc(dbFor('alice'), 'libraryBooks/alice-copy')));
  await assertSucceeds(getDoc(doc(dbFor('bob'), 'libraryBooks/alice-copy')));
  await assertFails(getDoc(doc(dbFor('eve'), 'libraryBooks/alice-copy')));
});

test('relation personal data is protected by library permissions', async () => {
  await assertFails(updateDoc(doc(dbFor('bob'), 'libraryBooks/alice-copy'), {
    notes: ['Değiştirme'],
  }));
  await assertFails(updateDoc(doc(dbFor('bob'), 'libraryBooks/alice-copy'), {
    libraryId: 'bob',
  }));
  await assertSucceeds(updateDoc(doc(dbFor('alice'), 'books/book'), {
    title: 'Güncel kitap', titleSearch: 'güncel kitap',
  }));
  await assertSucceeds(updateDoc(doc(dbFor('alice'), 'friendLinks/alice_bob'), {
    'permissions.bob': 'edit',
  }));
  await assertSucceeds(updateDoc(doc(dbFor('bob'), 'libraryBooks/alice-copy'), {
    notes: ['Bob edit'],
  }));
});

test('editors can add and remove relations in a shared library', async () => {
  const alice = dbFor('alice');
  const bob = dbFor('bob');
  await assertSucceeds(updateDoc(doc(alice, 'friendLinks/alice_bob'), {
    'permissions.bob': 'edit',
  }));
  const sharedCopy = doc(bob, 'libraryBooks/bob-added');
  await assertSucceeds(setDoc(sharedCopy, {
    libraryId: 'alice', bookId: 'book', status: 'Okunacak',
    wishlist: false, inHomeLibrary: true,
  }));
  await assertSucceeds(deleteDoc(sharedCopy));
});

test('canonical book is deleted only after its last library relation', async () => {
  const alice = dbFor('alice');
  const firstDelete = writeBatch(alice);
  firstDelete.delete(doc(alice, 'libraryBooks/alice-copy'));
  firstDelete.update(doc(alice, 'books/book'), {
    libraryCount: 1, libraryOwnerCounts: {bob: 1},
  });
  await assertSucceeds(firstDelete.commit());
  await assertSucceeds(getDoc(doc(dbFor('bob'), 'books/book')));

  const bob = dbFor('bob');
  const lastDelete = writeBatch(bob);
  lastDelete.delete(doc(bob, 'libraryBooks/bob-copy'));
  lastDelete.delete(doc(bob, 'books/book'));
  await assertSucceeds(lastDelete.commit());
});

test('ratings belong to a library relation', async () => {
  const alice = dbFor('alice');
  await assertSucceeds(setDoc(doc(alice, 'libraryBooks/alice-copy/ratings/alice'), {
    userId: 'alice', value: 5,
  }));
  await assertSucceeds(deleteDoc(doc(alice, 'libraryBooks/alice-copy/ratings/alice')));
  await assertFails(setDoc(doc(dbFor('eve'), 'libraryBooks/alice-copy/ratings/eve'), {
    userId: 'eve', value: 5,
  }));
  await assertFails(setDoc(doc(alice, 'books/book/ratings/alice'), {
    userId: 'alice', value: 5,
  }));
});

test('favorites belong to a library relation', async () => {
  const alice = dbFor('alice');
  await assertSucceeds(setDoc(doc(alice, 'libraryBooks/alice-copy/favorites/alice'), {
    userId: 'alice',
  }));
  await assertSucceeds(deleteDoc(doc(alice, 'libraryBooks/alice-copy/favorites/alice')));
  await assertSucceeds(setDoc(doc(dbFor('bob'), 'libraryBooks/alice-copy/favorites/bob'), {
    userId: 'bob',
  }));
  await assertFails(setDoc(doc(dbFor('eve'), 'libraryBooks/alice-copy/favorites/eve'), {
    userId: 'eve',
  }));
  await assertFails(setDoc(doc(alice, 'libraryBooks/alice-copy/favorites/bob'), {
    userId: 'alice',
  }));
  await assertFails(setDoc(doc(alice, 'libraryBooks/alice-copy/favorites/alice'), {
    userId: 'eve',
  }));
});

const loan = {
  bookId: 'alice-copy', ownerId: 'alice', requesterId: 'bob',
  requesterName: '@bob', bookTitle: 'Kitap', status: 'pending',
};
test('loan requests and approvals reference a library relation', async () => {
  await assertFails(setDoc(doc(dbFor('eve'), 'loanRequests/alice-copy_eve'), {
    ...loan, requesterId: 'eve',
  }));
  await assertSucceeds(setDoc(doc(dbFor('bob'), 'loanRequests/alice-copy_bob'), loan));
  await assertFails(setDoc(doc(dbFor('bob'), 'loanRequests/alice-copy_bob'), {
    ...loan, ownerId: 'eve',
  }));

  const alice = dbFor('alice');
  await assertFails(updateDoc(doc(alice, 'loanRequests/alice-copy_bob'), {
    status: 'approved',
  }));
  const approval = writeBatch(alice);
  approval.update(doc(alice, 'loanRequests/alice-copy_bob'), {status: 'approved'});
  approval.update(doc(alice, 'libraryBooks/alice-copy'), {
    borrower: '@bob', borrowerUserId: 'bob', loanRequestId: 'alice-copy_bob',
  });
  await assertSucceeds(approval.commit());
  await assertFails(setDoc(doc(dbFor('bob'), 'loanRequests/alice-copy_bob'), loan));

  await updateDoc(doc(alice, 'libraryBooks/alice-copy'), {borrower: null, borrowerUserId: null});
  await assertSucceeds(setDoc(doc(dbFor('bob'), 'loanRequests/alice-copy_bob'), loan));
});

test('notifications can only be created for a related loan', async () => {
  const alice = dbFor('alice');
  const bob = dbFor('bob');
  const request = writeBatch(bob);
  request.set(doc(bob, 'loanRequests/alice-copy_bob'), loan);
  request.set(doc(bob, 'notifications/request'), {
    bookId: 'alice-copy', requestId: 'alice-copy_bob', toId: 'alice',
    fromId: 'bob', type: 'loanRequest', read: false,
  });
  await assertSucceeds(request.commit());
  await assertSucceeds(getDocs(query(
    collection(alice, 'notifications'), where('toId', '==', 'alice'),
  )));
  await assertSucceeds(updateDoc(doc(alice, 'notifications/request'), {read: true}));
  await assertFails(updateDoc(doc(alice, 'notifications/request'), {toId: 'eve'}));
  await assertFails(setDoc(doc(alice, 'notifications/fake'), {
    bookId: 'alice-copy', requestId: 'missing', toId: 'alice',
    fromId: 'alice', type: 'loanRequest', read: false,
  }));
});
