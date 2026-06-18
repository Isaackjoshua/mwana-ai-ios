import 'dart:convert';
import 'dart:typed_data';

import '../vocabulary/sp_vocabulary.dart';
import 'tokenization_algorithm.dart';

/// Unigram tokenization algorithm using Viterbi decoding.
///
/// Finds the optimal segmentation by maximizing the sum of log probabilities.
/// Used by Llama and other models trained with SentencePiece Unigram.
class UnigramAlgorithm implements TokenizationAlgorithm {
  final SpVocabulary vocab;
  final bool byteFallback;

  UnigramAlgorithm({required this.vocab, this.byteFallback = false});

  @override
  List<int> tokenize(String text) {
    if (text.isEmpty) return [];

    final n = text.length;

    // Viterbi DP arrays
    final bestScore = Float64List(n + 1);
    final bestPrev = Int32List(n + 1);
    final bestTokenId = Int32List(n + 1);

    // Initialize with negative infinity (using min finite value)
    for (var i = 0; i <= n; i++) {
      bestScore[i] = double.negativeInfinity;
      bestPrev[i] = -1;
      bestTokenId[i] = -1;
    }
    bestScore[0] = 0.0;

    // Forward pass
    for (var i = 0; i < n; i++) {
      if (bestScore[i] == double.negativeInfinity) continue;

      // Find all matching tokens at position i
      final matches = vocab.findAllPrefixes(text, i);

      if (matches.isNotEmpty) {
        for (final match in matches) {
          final j = match.end;
          final score = bestScore[i] + vocab.getScore(match.tokenId);

          if (score > bestScore[j]) {
            bestScore[j] = score;
            bestPrev[j] = i;
            bestTokenId[j] = match.tokenId;
          }
        }
      } else if (byteFallback && vocab.hasByteFallback) {
        // No matches, try byte fallback
        final byteTokens = _encodeCharAsBytes(text, i);
        if (byteTokens != null) {
          final (endPos, tokenIds, totalScore) = byteTokens;
          final score = bestScore[i] + totalScore;

          if (score > bestScore[endPos]) {
            bestScore[endPos] = score;
            bestPrev[endPos] = i;
            // Store first byte token, we'll handle multi-byte later
            bestTokenId[endPos] = _encodeByteFallbackMarker(tokenIds);
          }
        }
      } else {
        // Fallback to single character as UNK
        final charEnd = _getNextCharEnd(text, i);
        final score = bestScore[i] + vocab.getScore(vocab.unkId);

        if (score > bestScore[charEnd]) {
          bestScore[charEnd] = score;
          bestPrev[charEnd] = i;
          bestTokenId[charEnd] = vocab.unkId;
        }
      }
    }

    // Check if we reached the end
    if (bestScore[n] == double.negativeInfinity) {
      // Couldn't tokenize, return UNK for each character
      return _fallbackTokenize(text);
    }

    // Backtrack to get tokens
    return _backtrack(text, bestPrev, bestTokenId, n);
  }

  /// Encode a character at position as byte tokens.
  /// Returns (endPosition, tokenIds, totalScore) or null if not possible.
  (int, List<int>, double)? _encodeCharAsBytes(String text, int startIndex) {
    // Get the character at position (handle surrogate pairs)
    final charEnd = _getNextCharEnd(text, startIndex);
    final char = text.substring(startIndex, charEnd);
    final bytes = utf8.encode(char);

    final tokenIds = <int>[];
    var totalScore = 0.0;

    for (final byte in bytes) {
      final tokenId = vocab.valueToByteToken(byte);
      if (tokenId == null) {
        return null;
      }
      tokenIds.add(tokenId);
      totalScore += vocab.getScore(tokenId);
    }

    return (charEnd, tokenIds, totalScore);
  }

  /// Get the end index of the next character (handling surrogate pairs).
  int _getNextCharEnd(String text, int start) {
    if (start >= text.length) return text.length;

    final codeUnit = text.codeUnitAt(start);
    // Check for high surrogate
    if (codeUnit >= 0xD800 &&
        codeUnit <= 0xDBFF &&
        start + 1 < text.length) {
      final low = text.codeUnitAt(start + 1);
      // Check for low surrogate
      if (low >= 0xDC00 && low <= 0xDFFF) {
        return start + 2;
      }
    }
    return start + 1;
  }

  /// Encode byte fallback info into a negative marker.
  /// We use negative values to indicate byte fallback tokens.
  int _encodeByteFallbackMarker(List<int> tokenIds) {
    // For simplicity, we mark byte fallback with a special negative value
    // and reconstruct during backtracking
    return -tokenIds.length - 1;
  }

  /// Backtrack through the DP arrays to reconstruct the token sequence.
  List<int> _backtrack(
    String text,
    Int32List bestPrev,
    Int32List bestTokenId,
    int n,
  ) {
    final tokens = <int>[];
    var pos = n;

    while (pos > 0) {
      final tokenId = bestTokenId[pos];
      final prevPos = bestPrev[pos];

      if (tokenId < 0) {
        // Byte fallback - reconstruct byte tokens
        final char = text.substring(prevPos, pos);
        final bytes = utf8.encode(char);
        for (final byte in bytes) {
          final byteTokenId = vocab.valueToByteToken(byte);
          if (byteTokenId != null) {
            tokens.add(byteTokenId);
          } else {
            tokens.add(vocab.unkId);
          }
        }
      } else {
        tokens.add(tokenId);
      }

      pos = prevPos;
    }

    return tokens.reversed.toList();
  }

  /// Fallback tokenization when Viterbi fails to reach the end.
  List<int> _fallbackTokenize(String text) {
    final tokens = <int>[];

    var i = 0;
    while (i < text.length) {
      final matches = vocab.findAllPrefixes(text, i);

      if (matches.isNotEmpty) {
        // Use the longest match
        final best = matches.reduce(
          (a, b) => a.end > b.end ? a : b,
        );
        tokens.add(best.tokenId);
        i = best.end;
      } else if (byteFallback && vocab.hasByteFallback) {
        // Try byte fallback
        final charEnd = _getNextCharEnd(text, i);
        final char = text.substring(i, charEnd);
        final bytes = utf8.encode(char);

        for (final byte in bytes) {
          final tokenId = vocab.valueToByteToken(byte);
          if (tokenId != null) {
            tokens.add(tokenId);
          } else {
            tokens.add(vocab.unkId);
          }
        }
        i = charEnd;
      } else {
        // No match, emit UNK and advance one character
        tokens.add(vocab.unkId);
        i = _getNextCharEnd(text, i);
      }
    }

    return tokens;
  }
}
