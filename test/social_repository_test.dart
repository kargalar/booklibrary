import 'package:booklibrary/data/social_repository.dart';
import 'package:booklibrary/data/library_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('friend link id is stable regardless of user order', () {
    expect(friendLinkId('user-b', 'user-a'), 'user-a_user-b');
    expect(friendLinkId('user-a', 'user-b'), 'user-a_user-b');
  });

  test('usernames normalize handles and rejects invalid values', () {
    expect(normalizeUsername('@Kitap_Sever'), 'kitap_sever');
    expect(normalizeUsername('ab'), isNull);
    expect(normalizeUsername('kitap sever'), isNull);
  });

  test('catalog search key normalizes Turkish titles and spaces', () {
    expect(normalizeBookSearchText('Küçük   Prens'), 'kucuk prens');
  });
}
