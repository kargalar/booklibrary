part of 'library_page.dart';

class _RenameLibrarySheet extends StatefulWidget {
  const _RenameLibrarySheet({
    required this.initialName,
    this.title = 'Change library name',
  });

  final String initialName;
  final String title;

  @override
  State<_RenameLibrarySheet> createState() => _RenameLibrarySheetState();
}
