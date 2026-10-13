import 'package:flutter_test/flutter_test.dart';

import 'package:booklibrary/data/borrower_repository.dart';

void main() {
  test('borrower keeps its Firestore id and name', () {
    const borrower = Borrower(id: 'person-1', name: 'Ada');

    expect(borrower.id, 'person-1');
    expect(borrower.name, 'Ada');
  });
}
