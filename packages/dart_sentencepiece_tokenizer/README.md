# dart_sentencepiece_tokenizer

![Dart](https://img.shields.io/badge/Dart-3.10.7+-0175C2.svg?logo=dart)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)
![Hugging Face](https://img.shields.io/badge/%F0%9F%A4%97%20Hugging%20Face-Compatible-FF6600)

A lightweight, pure Dart implementation of SentencePiece tokenizer. Supports BPE (Gemma) and Unigram (Llama) algorithms.

## Features

- **Pure Dart** - Zero dependencies, works everywhere (Flutter, Server, CLI, Web)
- **Memory Efficient** - Typed arrays (`Int32List`, `Uint8List`) for 50-70% memory reduction
- **BPE & Unigram** - Supports both algorithms used by Gemma and Llama models
- **Optimized BPE** - O(1) merge operations with linked list and merge caching
- **Full API** - Encoding, decoding, padding, truncation, offset mapping
- **Batch Processing** - Sequential and parallel (Isolate-based) batch encoding
- **Streaming API** - HuggingFace TextStreamer compatible for real-time LLM output
- **HuggingFace Compatible** - JSON serialization, dynamic token addition, tokenize() API
- **Well Tested** - 274 tests with 100% pass rate

## Installation

```yaml
dependencies:
  dart_sentencepiece_tokenizer: ^1.3.0
```

## Quick Start

```dart
import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';

void main() {
  // Load tokenizer with Llama config (BOS only)
  final tokenizer = SentencePieceTokenizer.fromModelFileSync(
    'tokenizer.model',
    config: SentencePieceConfig.llama,
  );

  // Encode text
  final encoding = tokenizer.encode('Hello, world!');
  print(encoding.tokens); // [<s>, ▁Hello, ,, ▁world, !]
  print(encoding.ids);    // [1, 15043, 29892, 3186, 29991]

  // Decode back to text
  final text = tokenizer.decode(encoding.ids, skipSpecialTokens: true);
  print(text); // Hello, world!
}
```

## Usage

### Single Text Encoding

```dart
final encoding = tokenizer.encode('Hello world');

print(encoding.tokens);           // Token strings
print(encoding.ids);              // Token IDs (Int32List)
print(encoding.attentionMask);    // Attention mask (Uint8List)
print(encoding.typeIds);          // Type IDs (Uint8List)
print(encoding.offsets);          // Character offsets [(start, end), ...]
print(encoding.wordIds);          // Word indices
print(encoding.sequenceIds);      // Sequence indices (0, 1, or null)

// Without special tokens
final raw = tokenizer.encode('Hello', addSpecialTokens: false);
```

> **Note:** Input text exceeding 500,000 characters throws `ArgumentError` to prevent OOM.

### Sentence Pair Encoding

```dart
// For QA, NLI, sentence similarity tasks
final encoding = tokenizer.encodePair(
  'What is machine learning?',
  'Machine learning is a subset of AI.',
);

print(encoding.typeIds);     // [0,0,0,0,0,0, 1,1,1,1,1,1,1]
print(encoding.sequenceIds); // [null,0,0,0,0,null, 1,1,1,1,1,1,null]

// With truncation
final encoding = tokenizer.encodePair(
  longQuestion,
  longAnswer,
  maxLength: 512,
  strategy: TruncationStrategy.longestFirst,
);
```

### Batch Encoding

```dart
// Sequential batch
final encodings = tokenizer.encodeBatch(['Hello', 'World', 'Test']);

// Parallel batch (uses Isolates for batches >= 8)
final encodings = await tokenizer.encodeBatchParallel(texts);

// Pair batch
final pairs = [('Q1', 'A1'), ('Q2', 'A2')];
final encodings = tokenizer.encodePairBatch(pairs, maxLength: 256);
```

### Padding

```dart
// Fluent API
final tokenizer = SentencePieceTokenizer.fromModelFileSync('model.model')
  ..enablePadding(length: 512, direction: SpPaddingDirection.right);

// Or pad to longest in batch
tokenizer.enablePadding(); // Auto-pads to longest

// Manual padding
final padded = encoding.withPadding(
  targetLength: 128,
  padTokenId: tokenizer.vocab.padId,
  padOnRight: true,
);

// Pad to multiple of N
final padded = encoding.withPaddingToMultipleOf(
  multiple: 8,
  padTokenId: tokenizer.vocab.padId,
);
```

### Truncation

```dart
// Fluent API
final tokenizer = SentencePieceTokenizer.fromModelFileSync('model.model')
  ..enableTruncation(maxLength: 512, direction: SpTruncationDirection.right);

// Manual truncation
final truncated = encoding.withTruncation(maxLength: 64);

// Truncation strategies for pairs
final (truncA, truncB) = Encoding.truncatePair(
  encodingA: encodingA,
  encodingB: encodingB,
  maxLength: 128,
  strategy: TruncationStrategy.longestFirst,
);
```

**Truncation Strategies:**
- `longestFirst` - Remove from longest sequence iteratively
- `onlyFirst` - Truncate first sequence only
- `onlySecond` - Truncate second sequence only
- `doNotTruncate` - No truncation

### Offset Mapping

```dart
final encoding = tokenizer.encode('Hello world');

// Character position -> Token index
final tokenIdx = encoding.charToToken(6); // 'w' -> token index

// Token index -> Character span
final (start, end) = encoding.tokenToChars(1)!; // token -> (0, 5)

// Word index -> Token span
final (startToken, endToken) = encoding.wordToTokens(0)!;

// Token -> Word index
final wordIdx = encoding.tokenToWord(1);

// Token -> Sequence index (0, 1, or null for special tokens)
final seqIdx = encoding.tokenToSequence(1);
```

### Vocabulary Access

```dart
print(tokenizer.vocabSize);     // 32000
print(tokenizer.vocab.unkId);   // 0
print(tokenizer.vocab.bosId);   // 1
print(tokenizer.vocab.eosId);   // 2
print(tokenizer.vocab.padId);   // -1 (if not defined)

// Token <-> ID conversion
tokenizer.convertTokensToIds(['▁hello', '▁world']); // [15043, 3186]
tokenizer.convertIdsToTokens([15043, 3186]);         // ['▁hello', '▁world']

// Check if token exists
tokenizer.vocab.contains('▁hello'); // true

// Get vocabulary map (HuggingFace compatible)
final vocabMap = tokenizer.getVocab(); // Map<String, int>
final vocabWithAdded = tokenizer.getVocab(withAddedTokens: true);
```

### HuggingFace-Compatible Tokenize

```dart
// Returns List<String> instead of Encoding (HuggingFace compatible)
final tokens = tokenizer.tokenize('Hello world');
print(tokens); // ['▁Hello', '▁world']

// Batch tokenization
final tokensBatch = tokenizer.tokenizeBatch(['Hello', 'World']);
```

### Dynamic Token Addition

```dart
// Add new tokens to vocabulary
final added = tokenizer.addTokens(['[CUSTOM1]', '[CUSTOM2]']);
print('Added $added tokens');

// Add special tokens
tokenizer.addSpecialTokens({
  'pad_token': '[PAD]',
  'mask_token': '[MASK]',
  'cls_token': '[CLS]',
  'sep_token': '[SEP]',
});

// Check added tokens
print(tokenizer.getAddedVocab()); // {'[CUSTOM1]': 32000, ...}
print(tokenizer.isAddedToken('[CUSTOM1]')); // true
```

### JSON Serialization

```dart
// Save to HuggingFace tokenizer.json format
await tokenizer.saveToJson('tokenizer.json');
tokenizer.saveToJsonSync('tokenizer.json');

// Or get JSON string
final jsonString = tokenizer.toJson();

// Load from JSON
final loaded = await TokenizerJsonLoader.fromJsonFile('tokenizer.json');
final loadedSync = TokenizerJsonLoader.fromJsonFileSync('tokenizer.json');
final fromString = TokenizerJsonLoader.fromJsonString(jsonString);
```

### Decoding

```dart
// Decode with special tokens
final text = tokenizer.decode(encoding.ids, skipSpecialTokens: false);

// Decode without special tokens (default: true)
final text = tokenizer.decode(encoding.ids);

// Batch decode
final texts = tokenizer.decodeBatch(idsBatch);
```

### Streaming API (v1.3.0+)

Real-time token decoding for LLM output, compatible with HuggingFace's TextStreamer.

```dart
// Basic streaming with default stdout output
final streamer = tokenizer.createTextStreamer();
for (final tokenId in llmOutput) {
  streamer.put(tokenId);
}
streamer.end();

// Custom callback for streaming
final streamer = tokenizer.createTextStreamer(
  onFinalizedText: (text, {required streamEnd}) {
    myTextController.append(text);
    if (streamEnd) myTextController.complete();
  },
);

// Stream-based decoding
final textStream = tokenizer.decodeStream(llmTokenStream);
await for (final chunk in textStream) {
  stdout.write(chunk);
}

// Callback-based decoding
tokenizer.decodeWithCallback(
  tokenIds,
  (chunk) => stdout.write(chunk),
);

// Skip prompt tokens (useful for chat models)
final streamer = tokenizer.createTextStreamer(
  skipPrompt: true,
  promptLength: 10, // Skip first 10 tokens
);
```

**Streaming Features:**
- Word boundary heuristics for clean text emission
- CJK character detection for immediate output
- Skip special tokens option
- Skip prompt tokens with configurable length

## ONNX Runtime Integration

Use with ONNX Runtime for on-device ML inference:

```dart
import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'dart:typed_data';

final tokenizer = SentencePieceTokenizer.fromModelFileSync('model.model',
    config: SentencePieceConfig.llama)
  ..enableTruncation(maxLength: 512);

final encoding = tokenizer.encode('What is machine learning?');

// Encoding.ids is already Int32List, convert to Int64List for ONNX
final inputIds = Int64List.fromList(encoding.ids);
final attentionMask = Int64List.fromList(encoding.attentionMask);

// Pass to ONNX session
// final outputs = await session.run({
//   'input_ids': inputIds,
//   'attention_mask': attentionMask,
// });
```

## Configuration

```dart
// Gemma: adds BOS and EOS tokens
final gemmaTokenizer = SentencePieceTokenizer.fromModelFileSync(
  'gemma.model',
  config: SentencePieceConfig.gemma,
);

// Llama: adds BOS token only
final llamaTokenizer = SentencePieceTokenizer.fromModelFileSync(
  'llama.model',
  config: SentencePieceConfig.llama,
);

// Custom configuration
final customTokenizer = SentencePieceTokenizer.fromModelFileSync(
  'model.model',
  config: const SentencePieceConfig(
    addBosToken: true,
    addEosToken: false,
  ),
);
```

| Config | BOS Token | EOS Token | Use Case |
|--------|-----------|-----------|----------|
| `SentencePieceConfig()` | No | No | Raw tokenization |
| `SentencePieceConfig.gemma` | Yes | Yes | Gemma models |
| `SentencePieceConfig.llama` | Yes | No | Llama models |

## API Reference

### SentencePieceTokenizer

| Method | Description |
|--------|-------------|
| `fromModelFile(path, config?)` | Load from .model file (async) |
| `fromModelFileSync(path, config?)` | Load from .model file (sync) |
| `fromBytes(bytes, config?)` | Load from byte data |
| `encode(text, addSpecialTokens?)` | Encode single text |
| `encodePair(textA, textB, ...)` | Encode text pair |
| `encodeBatch(texts, addSpecialTokens?)` | Encode multiple texts |
| `encodeBatchParallel(texts, ...)` | Parallel batch encoding |
| `encodePairBatch(pairs, ...)` | Batch encode text pairs |
| `decode(ids, skipSpecialTokens?)` | Decode IDs to text |
| `decodeBatch(idsBatch, ...)` | Batch decode |
| `enablePadding()` / `noPadding()` | Configure padding |
| `enableTruncation()` / `noTruncation()` | Configure truncation |
| `convertTokensToIds(tokens)` | Convert tokens to IDs |
| `convertIdsToTokens(ids)` | Convert IDs to tokens |
| `numSpecialTokensToAdd(isPair?)` | Get special token count |
| `tokenize(text)` | Get token strings (HuggingFace compatible) |
| `tokenizeBatch(texts)` | Batch tokenization |
| `getVocab(withAddedTokens?)` | Get vocabulary as Map |
| `addTokens(tokens)` | Add tokens to vocabulary |
| `addSpecialTokens(tokens)` | Add special tokens |
| `getAddedVocab()` | Get dynamically added tokens |
| `isAddedToken(token)` | Check if token was added |
| `toJson()` | Serialize to JSON string |
| `saveToJson(path)` | Save to JSON file (async) |
| `saveToJsonSync(path)` | Save to JSON file (sync) |
| `createTextStreamer(...)` | Create HuggingFace-compatible streamer |
| `decodeStream(tokenStream)` | Decode token stream to text stream |
| `decodeWithCallback(ids, callback)` | Decode with callback |

### TextStreamer

| Method | Description |
|--------|-------------|
| `put(tokenId)` | Add token to stream |
| `end()` | Signal end of generation |
| `reset()` | Reset internal state |

### TokenizerJsonLoader

| Method | Description |
|--------|-------------|
| `fromJsonString(json)` | Load from JSON string |
| `fromJsonFile(path)` | Load from JSON file (async) |
| `fromJsonFileSync(path)` | Load from JSON file (sync) |

### Encoding

| Property | Type | Description |
|----------|------|-------------|
| `tokens` | `List<String>` | Token strings |
| `ids` | `Int32List` | Token IDs |
| `attentionMask` | `Uint8List` | Attention mask (1=attend, 0=ignore) |
| `typeIds` | `Uint8List` | Token type IDs (0=first, 1=second) |
| `specialTokensMask` | `Uint8List` | Special token mask |
| `offsets` | `List<(int, int)>` | Character offsets |
| `wordIds` | `List<int?>` | Word indices |
| `sequenceIds` | `List<int?>` | Sequence indices |
| `length` | `int` | Number of tokens |

## Performance

| Metric | Value |
|--------|-------|
| Throughput | ~500K+ tokens/sec |
| Model loading | ~50ms (32K vocab) |
| Memory (vocab) | ~3MB |
| Lookup complexity | O(k) per token |
| BPE merge | O(1) per merge |
| Max input length | 500,000 chars |

### Memory Efficiency

Uses typed arrays for 50-70% memory reduction:

| Field | Type | Bytes/token |
|-------|------|-------------|
| `ids` | `Int32List` | 4 |
| `typeIds` | `Uint8List` | 1 |
| `attentionMask` | `Uint8List` | 1 |
| `specialTokensMask` | `Uint8List` | 1 |

## Model File

Download SentencePiece models from HuggingFace:

- [Llama 2](https://huggingface.co/meta-llama/Llama-2-7b-hf/resolve/main/tokenizer.model)
- [Gemma](https://huggingface.co/google/gemma-7b/resolve/main/tokenizer.model)

Format: Binary protobuf (.model files from SentencePiece C++ library).

## Testing

```bash
# Run all tests (274 tests)
dart test

# Run specific test file
dart test test/sentencepiece_test.dart

# Run benchmarks
dart run benchmark/performance_benchmark.dart

# Run HuggingFace compatibility benchmark
dart run benchmark/hf_compatibility_benchmark.dart

# Run streaming benchmark
dart run benchmark/streaming_benchmark.dart
```

### HuggingFace Compatibility Verification

```bash
# Run HuggingFace compatibility benchmark
dart run benchmark/hf_compatibility_benchmark.dart

# Regenerate benchmark expected values (requires Python + sentencepiece)
pip install sentencepiece
python scripts/generate_hf_benchmark_data.py --model tokenizer.model
```

## License

MIT License
