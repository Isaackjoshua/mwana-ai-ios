import 'dart:math';

import 'package:local_hnsw/local_hnsw.item.dart';
import 'package:local_hnsw/local_hnsw.result.dart';

enum LocalHnswMetric {
  euclidean,
  cosine,
}

class LocalHNSW<V> {
  final int M;
  final int ef;
  final int dim;
  final LocalHnswMetric metric;
  final Random _rng = Random();

  final List<_Node<V>> _nodes = [];
  _Node<V>? _entryPoint;
  int _maxLevel = 0;

  LocalHNSW({
    required this.dim,
    this.M = 8,
    this.ef = 16,
    this.metric = LocalHnswMetric.euclidean,
  });

  void add(LocalHnswItem<V> item) {
    if (item.vector.length != dim) throw Exception("Vector dimension mismatch");

    final newNode = _Node<V>(item);
    final level = _randomLevel();

    _nodes.add(newNode);

    if (_entryPoint == null) {
      _entryPoint = newNode;
      _maxLevel = level;
      return;
    }

    var ep = _entryPoint!;
    for (int l = _maxLevel; l >= 0; l--) {
      final result = _searchLayer(ep, item.vector, 1, l);
      if (l <= level) {
        _connectNeighbors(newNode, result, l);
      }
      ep = result.first;
    }

    if (level > _maxLevel) {
      _maxLevel = level;
      _entryPoint = newNode;
    }
  }

  LocalHnswSearchResult<V> search(List<double> query, int k) {
    final start = DateTime.now();
    if (_entryPoint == null) {
      return LocalHnswSearchResult(duration: Duration.zero, items: [], visited: 0);
    }

    final visited = <_Node<V>>{};
    var ep = _entryPoint!;
    for (int l = _maxLevel; l > 0; l--) {
      final best = _searchLayer(ep, query, 1, l, visited);
      ep = best.first;
    }

    final results = _searchLayer(ep, query, ef, 0, visited);
    results.sort((a, b) => _distance(query, a.item.vector).compareTo(_distance(query, b.item.vector)));

    final items = results
        .take(k)
        .map(
          (node) => LocalHnswSearchResultItem(
            distance: _distance(query, node.item.vector),
            item: node.item.item,
          ),
        )
        .toList();

    final end = DateTime.now();

    return LocalHnswSearchResult(
      duration: end.difference(start),
      items: items,
      visited: visited.length,
    );
  }

  bool delete(V item) {
    final target = _nodes
        .where((n) => n.item.item == item)
        .cast<_Node<V>?>()
        .firstWhere((n) => n != null, orElse: () => null);
    if (target == null) return false;

    for (final level in target.links.keys) {
      for (final neighbor in target.links[level]!) {
        neighbor.links[level]?.remove(target);
      }
    }

    _nodes.remove(target);

    if (_entryPoint == target) {
      _entryPoint = _nodes.isEmpty ? null : _nodes.first;
      _maxLevel = _entryPoint == null
          ? 0
          : _entryPoint!.links.keys.isNotEmpty
              ? _entryPoint!.links.keys.reduce(max)
              : 0;
    }

    return true;
  }

  List<_Node<V>> _searchLayer(_Node<V> ep, List<double> query, int ef, int level, [Set<_Node<V>>? visitedSet]) {
    final visited = visitedSet ?? <_Node<V>>{};
    final candidates = <_Node<V>>[ep];
    final result = <_Node<V>>[ep];
    visited.add(ep);

    while (candidates.isNotEmpty) {
      final current = candidates.removeLast();
      final neighbors = current.links[level] ?? [];

      for (var neighbor in neighbors) {
        if (visited.contains(neighbor)) continue;
        visited.add(neighbor);
        candidates.add(neighbor);
        result.add(neighbor);
      }
    }

    result.sort((a, b) => _distance(query, a.item.vector).compareTo(_distance(query, b.item.vector)));
    return result.take(ef).toList();
  }

  void _connectNeighbors(_Node<V> node, List<_Node<V>> neighbors, int level) {
    node.links.putIfAbsent(level, () => []);
    final selected = neighbors.take(M).toList();

    node.links[level]!.addAll(selected);
    for (var n in selected) {
      n.links.putIfAbsent(level, () => []);
      if (n.links[level]!.length < M) {
        n.links[level]!.add(node);
      }
    }
  }

  int _randomLevel() {
    double prob = 1.0 / log(_nodes.length + 2);
    int level = 0;
    while (_rng.nextDouble() < prob && level < 5) level++;
    return level;
  }

  double _distance(List<double> a, List<double> b) {
    switch (metric) {
      case LocalHnswMetric.euclidean:
        double sum = 0;
        for (int i = 0; i < a.length; i++) {
          final diff = a[i] - b[i];
          sum += diff * diff;
        }
        return sqrt(sum);
      case LocalHnswMetric.cosine:
        double dot = 0, normA = 0, normB = 0;
        for (int i = 0; i < a.length; i++) {
          dot += a[i] * b[i];
          normA += a[i] * a[i];
          normB += b[i] * b[i];
        }
        if (normA == 0 || normB == 0) return 1.0;
        return 1.0 - (dot / (sqrt(normA) * sqrt(normB)));
    }
  }

  Map<String, dynamic> save({required String Function(V item) encodeItem}) {
    final data = _nodes
        .map((node) => {
              'item': encodeItem(node.item.item),
              'vector': node.item.vector,
            })
        .toList();

    return {
      'dim': dim,
      'M': M,
      'ef': ef,
      'metric': metric.name,
      'nodes': data,
    };
  }

  static LocalHNSW<V> load<V>({
    required Map<String, dynamic> json,
    required int dim,
    required V Function(String encodedItem) decodeItem,
    int M = 8,
    int ef = 16,
    LocalHnswMetric? metric,
  }) {
    final map = json;
    final index = LocalHNSW<V>(
      dim: dim,
      M: M,
      ef: ef,
      metric: metric ?? LocalHnswMetric.values.byName(map['metric'] ?? 'euclidean'),
    );
    final nodes = (map['nodes'] as List).cast<Map<String, dynamic>>();

    for (final node in nodes) {
      final vector = (node['vector'] as List).cast<num>().map((e) => e.toDouble()).toList();
      final item = decodeItem(node['item']);
      index.add(LocalHnswItem(item: item, vector: vector));
    }

    return index;
  }
}

class _Node<V> {
  final LocalHnswItem<V> item;
  final Map<int, List<_Node<V>>> links = {};

  _Node(this.item);
}
