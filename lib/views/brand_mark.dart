part of 'library_page.dart';

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mark = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        Icons.auto_stories_rounded,
        size: 24,
        color: scheme.onPrimary,
      ),
    );
    return Row(
      children: [
        mark,
        const SizedBox(width: 11),
        Text(
          'my library',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.4),
        ),
      ],
    );
  }
}
