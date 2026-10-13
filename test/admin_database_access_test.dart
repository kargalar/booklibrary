import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:booklibrary/views/admin_database_page.dart';

void main() {
  test('database panel is limited to the Windows admin account', () {
    expect(
      isDatabaseAdmin(
        platform: TargetPlatform.windows,
        email: 'M.ISLAM0422@GMAIL.COM',
      ),
      isTrue,
    );
    expect(
      isDatabaseAdmin(
        platform: TargetPlatform.android,
        email: 'm.islam0422@gmail.com',
      ),
      isFalse,
    );
    expect(
      isDatabaseAdmin(
        platform: TargetPlatform.windows,
        email: 'other@example.com',
      ),
      isFalse,
    );
  });
}
