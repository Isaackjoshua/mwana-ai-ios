class TrieNode {
  final Map<int, TrieNode> children = {};
  int? tokenId;
  String? token;
  bool get isEndOfToken => tokenId != null;
}

class Trie {
  final TrieNode _root = TrieNode();
  int _size = 0;

  int get size => _size;

  void insert(String token, int tokenId) {
    var node = _root;

    for (final codePoint in token.runes) {
      node = node.children.putIfAbsent(codePoint, () => TrieNode());
    }

    if (node.tokenId == null) {
      _size++;
    }
    node.tokenId = tokenId;
    node.token = token;
  }

  int? lookup(String token) {
    var node = _root;

    for (final codePoint in token.runes) {
      final child = node.children[codePoint];
      if (child == null) {
        return null;
      }
      node = child;
    }

    return node.tokenId;
  }

  bool contains(String token) => lookup(token) != null;

  /// Decode the code point at [index] in [text], handling surrogate pairs.
  /// Returns `(codePoint, nextIndex)` where nextIndex is the position after
  /// this code point (skips the low surrogate for surrogate pairs).
  static (int, int) _decodeCodePoint(String text, int index) {
    final codeUnit = text.codeUnitAt(index);
    if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF && index + 1 < text.length) {
      final low = text.codeUnitAt(index + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) {
        return (
          0x10000 + ((codeUnit - 0xD800) << 10) + (low - 0xDC00),
          index + 2,
        );
      }
    }
    return (codeUnit, index + 1);
  }

  TrieMatch? findLongestPrefix(String text, [int startIndex = 0]) {
    var node = _root;
    TrieMatch? lastMatch;

    var i = startIndex;
    while (i < text.length) {
      final (codePoint, nextI) = _decodeCodePoint(text, i);

      final child = node.children[codePoint];
      if (child == null) break;

      node = child;

      if (node.isEndOfToken) {
        lastMatch = TrieMatch(
          token: node.token!,
          tokenId: node.tokenId!,
          start: startIndex,
          end: nextI,
        );
      }
      i = nextI;
    }

    return lastMatch;
  }

  List<TrieMatch> findAllPrefixes(String text, [int startIndex = 0]) {
    final matches = <TrieMatch>[];
    var node = _root;

    var i = startIndex;
    while (i < text.length) {
      final (codePoint, nextI) = _decodeCodePoint(text, i);

      final child = node.children[codePoint];
      if (child == null) break;

      node = child;

      if (node.isEndOfToken) {
        matches.add(
          TrieMatch(
            token: node.token!,
            tokenId: node.tokenId!,
            start: startIndex,
            end: nextI,
          ),
        );
      }
      i = nextI;
    }

    return matches;
  }

  void clear() {
    _root.children.clear();
    _size = 0;
  }
}

class TrieMatch {
  final String token;
  final int tokenId;
  final int start;
  final int end;

  const TrieMatch({
    required this.token,
    required this.tokenId,
    required this.start,
    required this.end,
  });

  int get length => end - start;

  @override
  String toString() => 'TrieMatch(token: $token, id: $tokenId, [$start:$end])';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrieMatch &&
          token == other.token &&
          tokenId == other.tokenId &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(token, tokenId, start, end);
}
