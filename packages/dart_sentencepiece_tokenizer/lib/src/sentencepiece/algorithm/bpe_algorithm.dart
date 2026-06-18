import 'dart:convert';

import '../vocabulary/sp_vocabulary.dart';
import 'tokenization_algorithm.dart';

/// Node for doubly-linked list used in BPE merge operations.
class _BpeNode {
  String symbol;
  _BpeNode? prev;
  _BpeNode? next;

  _BpeNode(this.symbol);
}

class BpeAlgorithm implements TokenizationAlgorithm {
  final SpVocabulary vocab;
  final bool byteFallback;

  /// Cache for merged pair lookups: "symbol1\x00symbol2" -> (mergedString, score)
  final Map<String, (String, double)?> _mergeCache = {};

  static const _kMaxCacheSize = 10000;

  BpeAlgorithm({required this.vocab, this.byteFallback = false});

  @override
  List<int> tokenize(String text) {
    if (text.isEmpty) return [];

    // Initialize symbols as linked list for O(1) merge operations
    final (head, nodeCount) = _initializeSymbolList(text);
    if (head == null || nodeCount == 0) return [];

    var count = nodeCount;

    // Iteratively merge highest-scoring pairs
    while (count > 1) {
      final bestMerge = _findBestMerge(head);
      if (bestMerge == null) break;

      _applyMerge(bestMerge);
      count--;
    }

    // Collect results from linked list
    final result = <int>[];
    _BpeNode? node = head;
    while (node != null) {
      result.add(vocab.pieceToId(node.symbol));
      node = node.next;
    }
    return result;
  }

  (_BpeNode?, int) _initializeSymbolList(String text) {
    _BpeNode? head;
    _BpeNode? tail;
    var count = 0;

    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);

      void addNode(String symbol) {
        final node = _BpeNode(symbol);
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
      // Evict oldest half of cache entries
      final keys = _mergeCache.keys.toList();
      for (var i = 0; i < keys.length ~/ 2; i++) {
        _mergeCache.remove(keys[i]);
      }
    }
    return null;
  }

  _BpeNode? _findBestMerge(_BpeNode? head) {
    _BpeNode? bestNode;
    double bestScore = double.negativeInfinity;

    var node = head;
    while (node != null && node.next != null) {
      final result = _lookupMerge(node.symbol, node.next!.symbol);
      if (result != null) {
        final (_, score) = result;
        if (score > bestScore) {
          bestScore = score;
          bestNode = node;
        }
      }
      node = node.next;
    }

    return bestNode;
  }

  void _applyMerge(_BpeNode node) {
    final nextNode = node.next!;
    final result = _lookupMerge(node.symbol, nextNode.symbol);
    if (result == null) return;

    final (merged, _) = result;

    // Update current node with merged symbol
    node.symbol = merged;

    // Remove next node from linked list
    node.next = nextNode.next;
    if (nextNode.next != null) {
      nextNode.next!.prev = node;
    }
  }
}
