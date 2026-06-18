import 'package:test/test.dart';
import 'package:local_hnsw/local_hnsw.dart';
import 'package:local_hnsw/local_hnsw.item.dart';

void main() {
  group('LocalHNSW', () {
    late LocalHNSW<String> index;

    setUp(() {
      index = LocalHNSW<String>(dim: 3);
      index.add(LocalHnswItem(item: 'apple', vector: [0.1, 0.2, 0.3]));
      index.add(LocalHnswItem(item: 'banana', vector: [0.2, 0.1, 0.4]));
      index.add(LocalHnswItem(item: 'grape', vector: [0.9, 0.8, 0.7]));
    });

    test('search returns nearest neighbors', () {
      final result = index.search([0.1, 0.2, 0.3], 2);
      final found = result.items.map((e) => e.item).toList();
      expect(found, contains('apple'));
    });

    test('delete removes item', () {
      final deleted = index.delete('banana');
      expect(deleted, isTrue);

      final result = index.search([0.2, 0.1, 0.4], 3);
      final found = result.items.map((e) => e.item).toList();
      expect(found, isNot(contains('banana')));
    });

    test('delete returns false if item not found', () {
      final deleted = index.delete('not-found');
      expect(deleted, isFalse);
    });

    test('save and load preserves data', () {
      final json = index.save(encodeItem: (item) => item);
      final loaded = LocalHNSW.load<String>(
        json: json,
        dim: 3,
        decodeItem: (s) => s,
      );

      final result = loaded.search([0.1, 0.2, 0.3], 3);
      final found = result.items.map((e) => e.item).toList();
      expect(found, contains('apple'));
    });
  });
}
