part of 'reader_page.dart';

class _PdfPageNavigator extends StatelessWidget {
  const _PdfPageNavigator({
    required this.controller,
    required this.pageCount,
    required this.currentPage,
    required this.bookmarks,
    required this.onSelect,
  });

  final PdfViewerController controller;
  final int pageCount;
  final int currentPage;
  final Set<int> bookmarks;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.grid_view_rounded),
            title: Text('All pages'),
            subtitle: Text('Touch a page to open it directly'),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = (constraints.maxWidth / 112)
                    .floor()
                    .clamp(3, 8);
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 14,
                    childAspectRatio: .72,
                  ),
                  itemCount: pageCount,
                  itemBuilder: (context, index) {
                    final page = index + 1;
                    final selected = page == currentPage;
                    final bookmarked = bookmarks.contains(page);
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelect(page),
                      child: Column(
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: selected
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                            : Colors.transparent,
                                        width: selected ? 2 : 1,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(7),
                                      child: _PdfPageThumbnail(
                                        controller: controller,
                                        pageNumber: page,
                                      ),
                                    ),
                                  ),
                                ),
                                if (bookmarked)
                                  const Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Icon(
                                      Icons.bookmark_rounded,
                                      color: Colors.orange,
                                      size: 18,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Page $page',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
