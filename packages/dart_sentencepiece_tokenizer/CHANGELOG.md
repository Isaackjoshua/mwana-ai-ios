# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-02-02

### Added

- **Streaming API (HuggingFace TextStreamer Compatible)**
  - `BaseStreamer` - Abstract interface for streaming token decoders with `put()` and `end()` methods
  - `TextStreamer` - HuggingFace TextStreamer-compatible class for real-time LLM token decoding
    - `put(int tokenId)` - Add tokens as they are generated
    - `end()` - Signal end of generation and flush remaining content
    - `onFinalizedText` callback for custom text handling
    - `skipSpecialTokens` option to filter BOS/EOS/PAD tokens
    - `skipPrompt` option to skip initial prompt tokens
    - `promptLength` option to skip multiple prompt tokens
    - Word boundary heuristics for clean text emission (newlines, CJK, spaces)
  - `SentencePieceTokenizer.createTextStreamer()` - Factory for TextStreamer
  - `SentencePieceTokenizer.decodeStream()` - Stream-based token decoding
  - `SentencePieceTokenizer.decodeWithCallback()` - Callback-based token decoding

### Usage Examples

**TextStreamer (HuggingFace-compatible):**

```dart
final streamer = tokenizer.createTextStreamer();
for (final id in llmOutput) {
  streamer.put(id);
}
streamer.end();

// With custom callback
final streamer = tokenizer.createTextStreamer(
  onFinalizedText: (text, {required streamEnd}) {
    myTextController.append(text);
    if (streamEnd) myTextController.complete();
  },
);
```

**Stream-based decoding:**

```dart
final textStream = tokenizer.decodeStream(llmTokenStream);
await for (final chunk in textStream) {
  stdout.write(chunk);
}
```

**Callback-based decoding:**

```dart
tokenizer.decodeWithCallback(
  tokenIds,
  (chunk) => stdout.write(chunk),
);
```

## [1.2.2] - 2025-01-28

### Changed

- Extracted duplicate surrogate pair decoding logic in `Trie` into shared `_decodeCodePoint` helper
- Cached computed `sequenceIds` in `Encoding` to avoid O(n) recomputation on repeated access
- Added merge cache size limit (10,000 entries) to `BpeAlgorithm` and `BpeAlgorithmOptimized` to prevent unbounded memory growth
- Replaced manual loops with `fillRange` for padding initialization in `Encoding.withPadding()`

## [1.2.1] - 2025-01-28

### Changed

- Optimized batch `addTokens()` to use single typed array allocation instead of per-token expansion (O(N) instead of O(N²))
- Added input validation and defensive error handling in JSON deserialization (`TokenizerJsonLoader`)
- Consolidated duplicate `_kMaxInputLength` constant declarations

## [1.2.0] - 2025-01-17

### Added

- **JSON Serialization** - HuggingFace-compatible tokenizer.json format
  - `toJson()` - Serialize tokenizer to JSON string
  - `saveToJson()` / `saveToJsonSync()` - Save to file
  - `TokenizerJsonLoader.fromJsonString()` - Load from JSON string
  - `TokenizerJsonLoader.fromJsonFile()` / `fromJsonFileSync()` - Load from file

- **Dynamic Token Addition API**
  - `addTokens(List<String>)` - Add new tokens to vocabulary
  - `addSpecialTokens(Map<String, String>)` - Add special tokens (pad, mask, etc.)
  - `getAddedVocab()` - Get map of dynamically added tokens
  - `isAddedToken(String)` - Check if token was added dynamically
  - `getVocab({withAddedTokens})` - Get full vocabulary as Map<String, int>

- **HuggingFace-compatible Methods**
  - `tokenize(String)` - Returns List<String> of tokens
  - `tokenizeBatch(List<String>)` - Batch tokenization

- **Optimized BPE Algorithm** (`BpeAlgorithmOptimized`)
  - O(n log n) complexity using priority queue (heap)
  - ~35% faster than original algorithm on medium-length text

### Changed

- `SpVocabulary` now uses growable list for dynamic token addition support

## [1.1.0] - 2025-01-04

### Added

- Input length validation (max 500,000 characters) to prevent OOM
- Example usage file (`example/example.dart`)

### Changed

- Improved BPE algorithm efficiency
- Enhanced error messages for input validation

## [1.0.0] - 2025-01-03

### Added

- Initial release of dart_sentencepiece_tokenizer
- Pure Dart implementation with zero external dependencies
- Support for BPE (Byte Pair Encoding) algorithm used by Gemma models
- Support for Unigram algorithm used by Llama models
- Viterbi algorithm implementation for optimal Unigram segmentation
- Byte fallback support for handling unknΩown characters
- Unicode-aware Trie for efficient vocabulary lookup
- Memory-efficient typed arrays (Int32List, Uint8List) for encodings

### Features

- `SentencePieceTokenizer` - Main tokenizer class
  - `fromBytes()` - Load from protobuf bytes
  - `fromModelFile()` / `fromModelFileSync()` - Load from .model file
  - `encode()` - Encode single text
  - `encodeBatch()` - Encode multiple texts
  - `encodeBatchParallel()` - Parallel batch encoding using Isolates
  - `encodePair()` - Encode text pairs for sequence classification
  - `encodePairBatch()` - Batch encode text pairs
  - `decode()` / `decodeBatch()` - Decode token IDs back to text

- `Encoding` class with:
  - `ids` - Token IDs (Int32List)
  - `tokens` - Token strings
  - `typeIds` - Segment type IDs (Uint8List)
  - `attentionMask` - Attention mask (Uint8List)
  - `specialTokensMask` - Special token indicators (Uint8List)
  - `offsets` - Character offsets for each token
  - `withPadding()` / `withTruncation()` - Post-processing methods
  - `truncatePair()` - Static method for pair truncation

- Predefined configurations:
  - `SentencePieceConfig.llama` - Llama-style (BOS only)
  - `SentencePieceConfig.gemma` - Gemma-style (BOS + EOS)

- Truncation strategies:
  - `longestFirst` - Truncate longer sequence first
  - `onlyFirst` - Only truncate first sequence
  - `onlySecond` - Only truncate second sequence
  - `doNotTruncate` - No truncation

- Padding options:
  - Left/right padding direction
  - Fixed length or pad to longest
  - Pad to multiple of N

### Performance

- Efficient Trie-based vocabulary lookup
- Memory-optimized typed arrays reduce memory usage by ~78%
- Parallel batch processing with configurable chunk size
- Lazy evaluation where possible

### Compatibility

- Dart SDK 3.10.7+
- Compatible with Llama, Gemma, and other SentencePiece models
- HuggingFace-compatible API design
