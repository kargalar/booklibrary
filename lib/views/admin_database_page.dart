import 'dart:convert';

import '../data/local_database.dart';
import '../data/local_identity.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const databaseAdminEmail = 'm.islam0422@gmail.com';

const _adminCollections = [
  'users',
  'usernames',
  'books',
  'libraryBooks',
  'borrowers',
  'friendRequests',
  'friendLinks',
  'loanRequests',
  'notifications',
  'catalogBooks',
];

bool isDatabaseAdmin({required TargetPlatform platform, String? email}) =>
    platform == TargetPlatform.windows &&
    email?.trim().toLowerCase() == databaseAdminEmail;

class AdminDatabasePage extends StatefulWidget {
  const AdminDatabasePage({super.key});

  @override
  State<AdminDatabasePage> createState() => _AdminDatabasePageState();
}

class _AdminDatabasePageState extends State<AdminDatabasePage> {
  final _database = LocalDatabase.instance;
  final _searchController = TextEditingController();
  String _collection = _adminCollections.first;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isDatabaseAdmin(
      platform: defaultTargetPlatform,
      email: LocalIdentity.instance.currentUser?.email,
    )) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin paneli')),
        body: const Center(
          child: Text('You do not have permission to access this panel.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Database management')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _collection,
                  decoration: const InputDecoration(
                    labelText: 'Collection',
                    prefixIcon: Icon(Icons.table_rows_rounded),
                  ),
                  items: [
                    for (final name in _adminCollections)
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _collection = value);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search by document ID or content',
                    prefixIcon: Icon(Icons.search_rounded),
                    suffixIcon: Icon(Icons.filter_alt_outlined),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // ponytail: first 200 documents; add cursor pagination when this ceiling matters.
              stream: _database.collection(_collection).limit(200).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _ErrorState(message: snapshot.error.toString());
                }
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final term = _searchController.text.trim().toLowerCase();
                final documents = (snapshot.data?.docs ?? const []).where((
                  document,
                ) {
                  if (term.isEmpty) return true;
                  final content = jsonEncode(
                    _encodeFirestoreValue(document.data()),
                  ).toLowerCase();
                  return document.id.toLowerCase().contains(term) ||
                      content.contains(term);
                }).toList();
                if (documents.isEmpty) {
                  return const Center(child: Text('Document not found.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  itemCount: documents.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final document = documents[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(document.id),
                        subtitle: Text(
                          _documentSummary(document.data()),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openEditor(
                          document.reference,
                          document.data(),
                          isNew: false,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(
          _database.collection(_collection).doc(),
          const {},
          isNew: true,
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Yeni belge'),
      ),
    );
  }

  Future<void> _openEditor(
    DocumentReference<Map<String, dynamic>> reference,
    Map<String, dynamic> data, {
    required bool isNew,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AdminDocumentEditorPage(
          reference: reference,
          initialData: data,
          isNew: isNew,
        ),
      ),
    );
  }
}

class AdminDocumentEditorPage extends StatefulWidget {
  const AdminDocumentEditorPage({
    super.key,
    required this.reference,
    required this.initialData,
    required this.isNew,
  });

  final DocumentReference<Map<String, dynamic>> reference;
  final Map<String, dynamic> initialData;
  final bool isNew;

  @override
  State<AdminDocumentEditorPage> createState() =>
      _AdminDocumentEditorPageState();
}

class _AdminDocumentEditorPageState extends State<AdminDocumentEditorPage> {
  late final TextEditingController _jsonController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _jsonController = TextEditingController(
      text: const JsonEncoder.withIndent('  ')
          .convert(_encodeFirestoreValue(widget.initialData)),
    );
  }

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.isNew ? 'Yeni belge' : 'Edit document'),
      actions: [
        if (!widget.isNew)
          IconButton(
            tooltip: 'delete document',
            onPressed: _saving ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        IconButton(
          tooltip: 'Save',
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded),
        ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.reference.parent.id}/${widget.reference.id}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Leave custom field flags unchanged to preserve Firestore types.',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _jsonController,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Belge JSON',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final decoded = jsonDecode(_jsonController.text);
      if (decoded is! Map) {
        throw const FormatException('The document root must be a JSON object.');
      }
      final restored = _decodeFirestoreValue(decoded);
      await widget.reference.set(Map<String, dynamic>.from(restored as Map));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $error')));
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this document?'),
        content: Text(
          'Document ${widget.reference.id} will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.reference.delete();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $error')));
      }
    }
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text('Could not load documents: $message'),
    ),
  );
}

String _documentSummary(Map<String, dynamic> data) => data.entries
    .take(3)
    .map((entry) => '${entry.key}: ${_displayValue(entry.value)}')
    .join(' · ');

String _displayValue(Object? value) {
  if (value is Map || value is Iterable) {
    return jsonEncode(_encodeFirestoreValue(value));
  }
  return '$value';
}

Object? _encodeFirestoreValue(Object? value) {
  if (value is Timestamp) {
    return {
      '__databaseType': 'timestamp',
      'value': value.toDate().toIso8601String(),
    };
  }
  if (value is GeoPoint) {
    return {
      '__databaseType': 'geoPoint',
      'latitude': value.latitude,
      'longitude': value.longitude,
    };
  }
  if (value is DocumentReference) {
    return {'__databaseType': 'reference', 'path': value.path};
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        '${entry.key}': _encodeFirestoreValue(entry.value),
    };
  }
  if (value is Iterable) return value.map(_encodeFirestoreValue).toList();
  return value;
}

Object? _decodeFirestoreValue(Object? value) {
  if (value is List) return value.map(_decodeFirestoreValue).toList();
  if (value is Map) {
    final type = value['__databaseType'];
    if (type == 'timestamp' && value['value'] is String) {
      return Timestamp.fromDate(DateTime.parse(value['value'] as String));
    }
    if (type == 'geoPoint' &&
        value['latitude'] is num &&
        value['longitude'] is num) {
      return GeoPoint(
        (value['latitude'] as num).toDouble(),
        (value['longitude'] as num).toDouble(),
      );
    }
    if (type == 'reference' && value['path'] is String) {
      return LocalDatabase.instance.doc(value['path'] as String);
    }
    return {
      for (final entry in value.entries)
        '${entry.key}': _decodeFirestoreValue(entry.value),
    };
  }
  return value;
}
