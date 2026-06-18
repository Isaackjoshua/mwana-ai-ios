import 'dart:io';

import 'base_streamer.dart';
import '../sentencepiece_tokenizer.dart';

/// Signature for the callback when finalized text is ready.
///
/// [text] is the decoded text chunk.
/// [streamEnd] is `true` when this is the final chunk (from [end]).
typedef OnFinalizedText = void Function(String text, {required bool streamEnd});

/// HuggingFace TextStreamer-compatible streaming decoder.
///
/// Converts LLM token output to text in real-time, matching HuggingFace's
/// `transformers.generation.streamers.TextStreamer` API.
///
/// The streamer uses word boundary heuristics to determine when to emit text:
/// - Newlines trigger immediate emission
/// - CJK characters are emitted immediately (no word boundary concerns)
/// - Otherwise, emits up to the last space to avoid splitting words
///
/// Example:
/// ```dart
/// final streamer = TextStreamer(tokenizer);
/// for (final tokenId in llmOutput) {
///   streamer.put(tokenId);
/// }
/// streamer.end();
/// ```
///
/// With custom callback:
/// ```dart
/// final streamer = TextStreamer(
///   tokenizer,
///   onFinalizedText: (text, {required streamEnd}) {
///     myTextController.append(text);
///     if (streamEnd) myTextController.complete();
///   },
/// );
/// ```
class TextStreamer implements BaseStreamer {
  final SentencePieceTokenizer _tokenizer;
  final bool _skipSpecialTokens;
  final bool _skipPrompt;
  final int _promptLength;

  /// Callback invoked when text is ready to be displayed.
  ///
  /// Override this to customize text output behavior. If not set,
  /// defaults to printing to stdout.
  OnFinalizedText? onFinalizedText;

  /// Accumulated token IDs for decoding.
  final List<int> _tokenCache = [];

  /// Number of characters already printed from current decode.
  int _printLen = 0;

  /// Number of prompt tokens remaining to skip.
  int _promptTokensRemaining = 0;

  /// Creates a TextStreamer for real-time token decoding.
  ///
  /// [tokenizer] - The SentencePiece tokenizer instance.
  /// [skipSpecialTokens] - Whether to skip special tokens like BOS/EOS.
  /// [skipPrompt] - Whether to skip initial prompt tokens. If true without
  ///   [promptLength], skips only the first token. Use [promptLength] to
  ///   specify exact number of prompt tokens to skip.
  /// [promptLength] - Number of prompt tokens to skip (requires [skipPrompt]).
  ///   Defaults to 1 when [skipPrompt] is true.
  /// [onFinalizedText] - Callback for finalized text chunks.
  TextStreamer(
    SentencePieceTokenizer tokenizer, {
    bool skipSpecialTokens = true,
    bool skipPrompt = false,
    int promptLength = 1,
    this.onFinalizedText,
  })  : _tokenizer = tokenizer,
        _skipSpecialTokens = skipSpecialTokens,
        _skipPrompt = skipPrompt,
        _promptLength = promptLength,
        _promptTokensRemaining = skipPrompt ? promptLength : 0;

  @override
  void put(int tokenId) {
    // Skip prompt tokens if configured
    if (_promptTokensRemaining > 0) {
      _promptTokensRemaining--;
      return;
    }

    _tokenCache.add(tokenId);

    // Decode all accumulated tokens
    final text = _tokenizer.decode(
      _tokenCache,
      skipSpecialTokens: _skipSpecialTokens,
    );

    // Determine how much text can be safely printed
    final printableText = _determinePrintableText(text);
    if (printableText.isNotEmpty) {
      _emitText(printableText, streamEnd: false);
      _printLen += printableText.length;
    }
  }

  @override
  void end() {
    // Flush any remaining buffered content
    if (_tokenCache.isNotEmpty) {
      final text = _tokenizer.decode(
        _tokenCache,
        skipSpecialTokens: _skipSpecialTokens,
      );
      final remaining = _printLen < text.length ? text.substring(_printLen) : '';
      if (remaining.isNotEmpty) {
        _emitText(remaining, streamEnd: true);
      } else {
        // Even if no remaining text, signal stream end
        _emitText('', streamEnd: true);
      }
    } else {
      // No tokens were added, still signal stream end
      _emitText('', streamEnd: true);
    }
    _reset();
  }

  /// Reset internal state for reuse.
  void reset() {
    _reset();
  }

  void _reset() {
    _tokenCache.clear();
    _printLen = 0;
    _promptTokensRemaining = _skipPrompt ? _promptLength : 0;
  }

  void _emitText(String text, {required bool streamEnd}) {
    if (onFinalizedText != null) {
      onFinalizedText!(text, streamEnd: streamEnd);
    } else {
      // Default behavior: print to stdout
      stdout.write(text);
      if (streamEnd) {
        stdout.writeln();
      }
    }
  }

  /// Determine how much text can be safely printed.
  ///
  /// Uses HuggingFace's heuristics:
  /// 1. If there's a newline, print up to and including it
  /// 2. If there's a CJK character at the end, print everything
  /// 3. Otherwise, print up to the last space (word boundary)
  String _determinePrintableText(String text) {
    if (_printLen >= text.length) {
      return '';
    }

    final unprintedText = text.substring(_printLen);
    if (unprintedText.isEmpty) {
      return '';
    }

    // Check for newline - flush up to and including it
    final newlineIndex = unprintedText.indexOf('\n');
    if (newlineIndex >= 0) {
      return unprintedText.substring(0, newlineIndex + 1);
    }

    // Check if the last character is CJK - print immediately
    // CJK characters don't have word boundary issues
    if (_isCjk(unprintedText.codeUnitAt(unprintedText.length - 1))) {
      return unprintedText;
    }

    // Find the last space to avoid splitting words
    final lastSpaceIndex = unprintedText.lastIndexOf(' ');
    if (lastSpaceIndex > 0) {
      // Print up to and including the space
      return unprintedText.substring(0, lastSpaceIndex + 1);
    }

    // No safe boundary found - buffer until we find one
    // Unless we have a lot of text, then flush anyway
    if (unprintedText.length > 4) {
      return unprintedText;
    }

    return '';
  }

  /// Check if a code unit is in CJK ranges.
  static bool _isCjk(int codeUnit) {
    // CJK Unified Ideographs
    if (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) return true;
    // CJK Unified Ideographs Extension A
    if (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) return true;
    // CJK Compatibility Ideographs
    if (codeUnit >= 0xF900 && codeUnit <= 0xFAFF) return true;
    // Hangul Syllables
    if (codeUnit >= 0xAC00 && codeUnit <= 0xD7AF) return true;
    // Hiragana
    if (codeUnit >= 0x3040 && codeUnit <= 0x309F) return true;
    // Katakana
    if (codeUnit >= 0x30A0 && codeUnit <= 0x30FF) return true;
    return false;
  }
}
