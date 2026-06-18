import 'dart:convert';

import '../vocabulary/sp_vocabulary.dart';
import 'tokenization_algorithm.dart';

/// Simple heap-based priority queue for BPE merge operations.
class _BpePriorityQueue<E extends Comparable<E>> {
  final List<E> _heap = [];

  bool get isEmpty => _heap.isEmpty;
  bool get isNotEmpty => _heap.isNotEmpty;
  int get length => _heap.length;

  void add(E element) {
    _heap.add(element);
    _siftUp(_heap.length - 1);
  }

  E removeFirst() {
    if (_heap.isEmpty) {
      throw StateError('Cannot remove from empty queue');
    }
    final result = _heap.first;
    if (_heap.length == 1) {
      _heap.removeLast();
    } else {
      _heap[0] = _heap.removeLast();
      _siftDown(0);
    }
    return result;
  }

  void _siftUp(int index) {
    var child = index;
    while (child > 0) {
      final parent = (child - 1) ~/ 2;
      if (_heap[child].compareTo(_heap[parent]) >= 0) break;
      _swap(child, parent);
      child = parent;
    }
  }

  void _siftDown(int index) {
    var parent = index;
    while (true) {
      final left = 2 * parent + 1;
      final right = 2 * parent + 2;
      var smallest = parent;

      if (left < _heap.length && _heap[left].compareTo(_heap[smallest]) < 0) {
        smallest = left;
      }
      if (right < _heap.length && _heap[right].compareTo(_heap[smallest]) < 0) {
        smallest = right;
      }

      if (smallest == parent) break;
      _swap(parent, smallest);
      parent = smallest;
    }
  }

  void _swap(int i, int j) {
    final temp = _heap[i];
    _heap[i] = _heap[j];
    _heap[j] = temp;
  }
}

/// Node for doubly-linked list used in BPE merge operations.
class _BpeNode {
  String symbol;
  _BpeNode? prev;
  _BpeNode? next;

  /// Unique index for tracking validity in priority queue.
  final int index;

  _BpeNode(this.symbol, this.index);
}

/// Represents a potential merge between two adjacent symbols.
class _MergePair implements Comparable<_MergePair> {
  final _BpeNode left;
  final String merged;
  final double score;

  /// Version number to detect stale entries in the priority queue.
  final int version;

  _MergePair({
    required this.left,
    required this.merged,
    required this.score,
    required this.version,
  });

  @override
  int compareTo(_MergePair other) {
    // Higher score = higher priority (max-heap behavior)
    final scoreCmp = other.score.compareTo(score);
    if (scoreCmp != 0) return scoreCmp;
    // Tie-breaker: prefer earlier positions for determinism
    return left.index.compareTo(other.left.index);
  }
}

/// Optimized BPE algorithm using a priority queue for O(n log n) complexity.
///
/// The standard BPE algorithm scans all pairs each iteration (O(n²)).
/// This version uses a priority queue to always merge the highest-scoring
/// pair in O(log n), achieving O(n log n) overall complexity.
class BpeAlgorithmOptimized implements TokenizationAlgorithm {
  final SpVocabulary vocab;
  final bool byteFallback;

  /// Cache for merged pair lookups: "symbol1\x00symbol2" -> (mergedString, score)
  final Map<String, (String, double)?> _mergeCache = {};

  static const _kMaxCacheSize = 10000;

  /// Version counter for each node position to invalidate stale queue entries.
  final Map<int, int> _nodeVersions = {};

  BpeAlgorithmOptimized({required this.vocab, this.byteFallback = false});

  @override
  List<int> tokenize(String text) {
    if (text.isEmpty) return [];

    // Reset version counters
    _nodeVersions.clear();

    // Initialize symbols as linked list
    final (head, nodeCount) = _initializeSymbolList(text);
    if (head == null || nodeCount == 0) return [];

    // Initialize priority queue with all valid merges
    final queue = _BpePriorityQueue<_MergePair>();
    _BpeNode? node = head;
    while (node != null && node.next != null) {
      _nodeVersions[node.index] = 0;
      final pair = _createMergePair(node, 0);
      if (pair != null) {
        queue.add(pair);
      }
      node = node.next;
    }
    // Don't forget the last node
    if (node != null) {
      _nodeVersions[node.index] = 0;
    }

    // Process merges from highest score to lowest
    while (queue.isNotEmpty) {
      final best = queue.removeFirst();

      // Skip stale entries (node was already merged)
      if (!_isValidPair(best)) continue;

      // Perform the merge
      _applyMerge(best.left, best.merged);

      // Invalidate old pairs involving this node or its former neighbor
      _incrementVersion(best.left.index);

      // Add new pairs for affected neighbors
      // Check left neighbor
      if (best.left.prev != null) {
        final newPair = _createMergePair(
          best.left.prev!,
          _nodeVersions[best.left.prev!.index]!,
        );
        if (newPair != null) {
          queue.add(newPair);
        }
      }

      // Check current node with new right neighbor
      if (best.left.next != null) {
        final newPair = _createMergePair(
          best.left,
          _nodeVersions[best.left.index]!,
        );
        if (newPair != null) {
          queue.add(newPair);
        }
      }
    }

    // Collect results from linked list
    return _collectResults(head);
  }

  (_BpeNode?, int) _initializeSymbolList(String text) {
    _BpeNode? head;
    _BpeNode? tail;
    var count = 0;
    var index = 0;

    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);

      void addNode(String symbol) {
        final node = _BpeNode(symbol, index++);
        if (head == null) {
          head = node;
          tail = node;
        } else {
          tail!.next = node;
          node.prev = tail;
          tail = node;
        }
        count++;
      }

      // Check if character exists in vocabulary
      if (vocab.contains(char)) {
        addNode(char);
      } else if (byteFallback) {
        // Encode as UTF-8 bytes and use byte tokens
        final bytes = utf8.encode(char);
        for (final byte in bytes) {
          final byteTokenId = vocab.valueToByteToken(byte);
          if (byteTokenId != null) {
            addNode(vocab.idToPiece(byteTokenId));
          } else {
            // Fallback to UNK if byte token not found
            addNode(vocab.unkPiece);
          }
        }
      } else {
        addNode(char);
      }
    }

    return (head, count);
  }

  _MergePair? _createMergePair(_BpeNode node, int version) {
    if (node.next == null) return null;

    final result = _lookupMerge(node.symbol, node.next!.symbol);
    if (result == null) return null;

    final (merged, score) = result;
    return _MergePair(
      left: node,
      merged: merged,
      score: score,
      version: version,
    );
  }

  bool _isValidPair(_MergePair pair) {
    // Check if the left node still exists and hasn't been modified
    if (pair.left.next == null) return false;

    final currentVersion = _nodeVersions[pair.left.index];
    if (currentVersion == null || currentVersion != pair.version) return false;

    return true;
  }

  void _incrementVersion(int index) {
    _nodeVersions[index] = (_nodeVersions[index] ?? 0) + 1;
  }

  /// Lookup merge result with caching.
  (String, double)? _lookupMerge(String left, String right) {
    final cacheKey = '$left\x00$right';

    if (_mergeCache.containsKey(cacheKey)) {
      return _mergeCache[cacheKey];
    }

    final merged = left + right;
    if (vocab.contains(merged)) {
      final id = vocab.pieceToId(merged);
      final score = vocab.getScore(id);
      final result = (merged, score);
      _mergeCache[cacheKey] = result;
      return result;
    }

    _mergeCache[cacheKey] = null;
    if (_mergeCache.length > _kMaxCacheSize) {
      final keys = _mergeCache.keys.toList();
      for (var i = 0; i < keys.length ~/ 2; i++) {
        _mergeCache.remove(keys[i]);
      }
    }
    return null;
  }

  void _applyMerge(_BpeNode node, String merged) {
    final nextNode = node.next!;

    // Update current node with merged symbol
    node.symbol = merged;

    // Remove next node from linked list
    node.next = nextNode.next;
    if (nextNode.next != null) {
      nextNode.next!.prev = node;
    }
  }

  List<int> _collectResults(_BpeNode? head) {
    final result = <int>[];
    _BpeNode? node = head;
    while (node != null) {
      result.add(vocab.pieceToId(node.symbol));
      node = node.next;
    }
    return result;
  }

  /// Clear the merge cache (useful for memory management).
  void clearCache() {
    _mergeCache.clear();
  }
}
