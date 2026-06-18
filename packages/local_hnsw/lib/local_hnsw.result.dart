class LocalHnswSearchResult<V> {
  final Duration duration;
  final List<LocalHnswSearchResultItem<V>> items;
  final int visited;

  LocalHnswSearchResult({required this.duration, required this.items, required this.visited});
}

class LocalHnswSearchResultItem<V> {
  final double distance;
  final V item;

  LocalHnswSearchResultItem({required this.distance, required this.item});
}
