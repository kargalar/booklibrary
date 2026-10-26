part of 'reader_page.dart';

const _epubSearchAnchor = 'reader-search-match';
typedef _EpubMatch = ({int section, int start, int end});

// ignore_for_file: invalid_use_of_protected_member
extension _ReaderEpubSearch on _ReaderPageState {
  Future<void> showEpubSearch() async {
    chromeTimer?.cancel();
    final texts = sections
        .map(
          (section) =>
              html_parser.parse(section.Content ?? '').body?.text ?? '',
        )
        .toList();
    var query = '';
    final selected = await showReaderSheet<_EpubMatch>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final pattern = query.trim().isEmpty
              ? null
              : RegExp(RegExp.escape(query.trim()), caseSensitive: false);
          final matches = <_EpubMatch>[
            if (pattern != null)
              for (var section = 0; section < texts.length; section++)
                for (final match in pattern.allMatches(texts[section]))
                  (section: section, start: match.start, end: match.end),
          ];
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: _ReaderLabels.searchBook,
                        hintText: _ReaderLabels.searchHint,
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) => update(() => query = value),
                    ),
                  ),
                  if (pattern != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      child: Text(
                        '${matches.length} results',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  Expanded(
                    child: pattern == null
                        ? const Center(child: Text(_ReaderLabels.searchPrompt))
                        : matches.isEmpty
                        ? const Center(child: Text(_ReaderLabels.noResults))
                        : ListView.builder(
                            itemCount: matches.length,
                            itemBuilder: (context, index) {
                              final match = matches[index];
                              final text = texts[match.section];
                              final start = (match.start - 45).clamp(
                                0,
                                text.length,
                              );
                              final end = (match.end + 100).clamp(
                                0,
                                text.length,
                              );
                              return ListTile(
                                title: Text(chapterTitle(match.section)),
                                subtitle: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: text.substring(
                                          start,
                                          match.start,
                                        ),
                                      ),
                                      TextSpan(
                                        text: text.substring(
                                          match.start,
                                          match.end,
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      TextSpan(
                                        text: text.substring(match.end, end),
                                      ),
                                    ],
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_rounded,
                                ),
                                onTap: () => Navigator.pop(context, match),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (selected == null || !mounted) return;
    go(selected.section);
    setState(
      () => highlightedEpubHtml = _highlightEpubMatch(
        sections[selected.section].Content ?? '',
        selected.start,
        selected.end,
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await htmlKey.currentState?.scrollToAnchor(_epubSearchAnchor);
  }
}

String _highlightEpubMatch(String html, int start, int end) {
  final document = html_parser.parse(html);
  var offset = 0;
  var anchorAdded = false;
  void visit(dom.Node node) {
    if (node is dom.Text) {
      final text = node.text;
      final nodeStart = offset;
      offset += text.length;
      if (nodeStart >= end || offset <= start) return;
      final from = (start - nodeStart).clamp(0, text.length);
      final to = (end - nodeStart).clamp(0, text.length);
      final wrapper = dom.Element.tag('span');
      if (from > 0) wrapper.append(dom.Text(text.substring(0, from)));
      final mark = dom.Element.tag('mark')
        ..attributes['style'] = 'background-color: #e8cc80; color: #292d32;'
        ..text = text.substring(from, to);
      if (!anchorAdded) {
        mark.id = _epubSearchAnchor;
        anchorAdded = true;
      }
      wrapper.append(mark);
      if (to < text.length) wrapper.append(dom.Text(text.substring(to)));
      node.replaceWith(wrapper);
    } else {
      for (final child in node.nodes.toList()) {
        visit(child);
      }
    }
  }

  if (document.body case final body?) visit(body);
  return document.outerHtml;
}
