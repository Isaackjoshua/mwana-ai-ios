class LocalHnswItem<V> {
  final V item;
  final List<double> vector;

  LocalHnswItem({required this.item, required this.vector});
}
