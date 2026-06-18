import 'package:local_hnsw/local_hnsw.dart';
import 'package:local_hnsw/local_hnsw.item.dart';

void main() {
  // Create an HNSW index for 3-dimensional vectors
  final index = LocalHNSW<String>(dim: 3);

  // Add items to the index
  index.add(LocalHnswItem(item: 'apple', vector: [0.1, 0.2, 0.3]));
  index.add(LocalHnswItem(item: 'banana', vector: [0.2, 0.1, 0.4]));
  index.add(LocalHnswItem(item: 'grape', vector: [0.9, 0.8, 0.7]));

  // Perform a search
  final result = index.search([0.1, 0.2, 0.3], 2);
  print('🔍 Search Results:');
  for (var item in result.items) {
    print(' - ${item.item} (distance: ${item.distance.toStringAsFixed(4)})');
  }
  print('Visited nodes: ${result.visited}');
  print('Search duration: ${result.duration.inMicroseconds} µs\n');

  // Delete an item
  final deleted = index.delete('banana');
  print(deleted ? '✅ Deleted "banana"\n' : '❌ Failed to delete "banana"\n');

  // Save the index to a map (you can later serialize this as JSON)
  final saved = index.save(encodeItem: (v) => v);
  print('🧠 Saved index: ${saved['nodes'].length} nodes\n');

  // Load the index from saved map
  final loaded = LocalHNSW.load<String>(
    json: saved,
    dim: 3,
    decodeItem: (s) => s,
  );

  // Search again on the loaded index
  final afterLoad = loaded.search([0.1, 0.2, 0.3], 3);
  print('🔁 Search after loading:');
  for (var item in afterLoad.items) {
    print(' - ${item.item} (distance: ${item.distance.toStringAsFixed(4)})');
  }
}
