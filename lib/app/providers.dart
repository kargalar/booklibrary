import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/book_repository.dart';
import '../data/borrower_repository.dart';
import '../data/social_repository.dart';
import '../viewmodels/library_view_model.dart';
import 'theme_controller.dart';

final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => BookRepository(),
);

final borrowerRepositoryProvider = Provider<BorrowerRepository>(
  (ref) => BorrowerRepository(),
);

final socialRepositoryProvider = Provider<SocialRepository>(
  (ref) => SocialRepository(),
);

final libraryViewModelProvider = Provider<LibraryViewModel>(
  (ref) => LibraryViewModel(
    repository: ref.watch(bookRepositoryProvider),
    borrowers: ref.watch(borrowerRepositoryProvider),
  ),
);

final themeControllerProvider = ChangeNotifierProvider<ThemeController>((ref) {
  final controller = ThemeController();
  ref.onDispose(controller.dispose);
  return controller;
});
