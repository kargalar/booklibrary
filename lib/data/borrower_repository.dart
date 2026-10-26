import 'local_database.dart';

class Borrower {
  const Borrower({required this.id, required this.name});

  final String id;
  final String name;

  factory Borrower.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final name = document.data()['name'];
    return Borrower(
      id: document.id,
      name: name is String && name.trim().isNotEmpty ? name : 'Unnamed person',
    );
  }
}

class BorrowerRepository {
  BorrowerRepository({LocalDatabase? database})
    : _database = database ?? LocalDatabase.instance;

  final LocalDatabase _database;

  CollectionReference<Map<String, dynamic>> get _borrowers =>
      _database.collection('borrowers');

  Stream<QuerySnapshot<Map<String, dynamic>>> watch(String ownerId) =>
      _borrowers.where('ownerId', isEqualTo: ownerId).snapshots();

  Future<Borrower> add({required String ownerId, required String name}) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A person name is required.');
    }
    // ponytail: owner-scoped people until library membership/ACL is defined;
    // migrate to libraryId when shared libraries ship.
    final document = await _borrowers.add({
      'ownerId': ownerId,
      'name': trimmedName,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return Borrower(id: document.id, name: trimmedName);
  }
}
