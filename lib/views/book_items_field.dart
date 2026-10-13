import 'package:flutter/material.dart';

import '../data/book_facets.dart';

class BookItemsField extends StatefulWidget {
  const BookItemsField({
    super.key,
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  State<BookItemsField> createState() => _BookItemsFieldState();
}

class _BookItemsFieldState extends State<BookItemsField> {
  final input = TextEditingController();
  late List<String> items;
  var serialized = '';

  @override
  void initState() {
    super.initState();
    _readController();
  }

  void _readController() {
    items = normalizeBookItems(widget.controller.text.split('\n'));
    _syncController();
  }

  void _syncController() {
    serialized = items.join('\n');
    if (widget.controller.text != serialized) {
      widget.controller.text = serialized;
    }
  }

  void add() {
    final next = normalizeBookItems(input.text.split('\n'));
    if (next.isEmpty) return;
    setState(() {
      items = normalizeBookItems([...items, ...next]);
      input.clear();
      _syncController();
    });
  }

  void remove(String item) => setState(() {
    items = items.where((entry) => entry != item).toList();
    _syncController();
  });

  @override
  void didUpdateWidget(covariant BookItemsField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller ||
        widget.controller.text != serialized) {
      _readController();
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: input,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => add(),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: 'Type and add item',
            suffixIcon: IconButton(
              tooltip: 'Add item',
              onPressed: add,
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ),
        Wrap(
          spacing: 6,
          children: [
            for (final item in items)
              InputChip(label: Text(item), onDeleted: () => remove(item)),
          ],
        ),
      ],
    ),
  );
}
