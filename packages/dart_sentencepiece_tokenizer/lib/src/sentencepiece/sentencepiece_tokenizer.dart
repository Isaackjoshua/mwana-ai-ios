import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../encoding.dart';
import 'algorithm/bpe_algorithm.dart';
import 'algorithm/tokenization_algorithm.dart';
import 'algorithm/unigram_algorithm.dart';
import 'model/model_proto.dart';
import 'model/sentencepiece_model.dart';
import 'normalizer/sp_normalizer.dart';
import 'streaming/text_streamer.dart';
import 'vocabulary/sp_vocabulary.dart';

export '../encoding.dart' show Encoding, TruncationStrategy;
export 'model/model_proto.dart' show ModelType;

const _kMinBatchSizeForParallel = 8;

/// Maximum input text length in characters (1MB of UTF-16 characters).
/// Prevents OOM from extremely large inputs.
const _kMaxInputLength = 500000;

/// Padding direction for batch encoding.
enum SpPaddingDirection { right, left }

/// Padding configuration for SentencePiece tokenizer.
class SpPaddingConfig {
  final SpPaddingDirection direction;
  final int? length;
  final int? padToMultipleOf;

  const SpPaddingConfig({
    this.direction = SpPaddingDirection.right,
    this.length,
    this.padToMultipleOf,
  });
}

/// Truncation direction for encoding.
enum SpTruncationDirection { right, left }

/// Truncation configuration for SentencePiece tokenizer.
class SpTruncationConfig {
  final int maxLength;
  final SpTruncationDirection direction;

  const SpTruncationConfig({
    required this.maxLength,
    this.direction = SpTruncationDirection.right,
  });
}

/// Configuration for SentencePiece tokenizer.
class SentencePieceConfig {
  final bool addBosToken;
  final bool addEosToken;

  const SentencePieceConfig({
    this.addBosToken = false,
    this.addEosToken = false,
  });

  /// Gemma default configuration.
  static const gemma = SentencePieceConfig(
    addBosToken: true,
    addEosToken: true,
  );

  /// Llama default configuration.
  static const llama = SentencePieceConfig(
    addBosToken: true,
    addEosToken: false,
  );
}

/// Pure Dart SentencePiece tokenizer.
///
/// Supports both BPE (Gemma) and Unigram (Llama) algorithms.
class SentencePieceTokenizer {
  final SpVocabulary vocab;
  final SentencePieceConfig config;
  final SpNormalizer _normalizer;
  final TokenizationAlgorithm _algorithm;
  final ModelType modelType;

  /// Access normalizer for serialization.
  SpNormalizer get normalizer => _normalizer;

  SpPaddingConfig? _paddingConfig;
  SpTruncationConfig? _truncationConfig;

  SentencePieceTokenizer._({
    required this.vocab,
    required this.config,
    required SpNormalizer normalizer,
    required TokenizationAlgorithm algorithm,
    required this.modelType,
  })  : _normalizer = normalizer,
        _algorithm = algorithm;

  /// Load tokenizer from a .model file asynchronously.
  static Future<SentencePieceTokenizer> fromModelFile(
    String path, {
    SentencePieceConfig config = const SentencePieceConfig(),
  }) async {
    final model = await SentencePieceModelLoader.fromFile(path);
    return _createFromModel(model, config);
  }

  /// Load tokenizer from a .model file synchronously.
  static SentencePieceTokenizer fromModelFileSync(
    String path, {
    SentencePieceConfig config = const SentencePieceConfig(),
  }) {
    final model = SentencePieceModelLoader.fromFileSync(path);
    return _createFromModel(model, config);
  }

  /// Create tokenizer from model bytes.
  static SentencePieceTokenizer fromBytes(
    List<int> bytes, {
    SentencePieceConfig config = const SentencePieceConfig(),
  }) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final model = SentencePieceModelLoader.fromBytes(data);
    return _createFromModel(model, config);
  }

  static SentencePieceTokenizer _createFromModel(
    SentencePieceModel model,
    SentencePieceConfig config,
  ) {
    final vocab = SpVocabulary.fromModel(model);
    final normalizer = SpNormalizer.fromSpec(model.normalizerSpec);
    final algorithm = _createAlgorithm(model, vocab);

    return SentencePieceTokenizer._(
      vocab: vocab,
      config: config,
      normalizer: normalizer,
      algorithm: algorithm,
      modelType: model.trainerSpec.modelType,
    );
  }

  /// Create tokenizer from a SentencePieceModel.
  ///
  /// This is useful for creating tokenizers from JSON deserialization
  /// or other non-file sources.
  static SentencePieceTokenizer fromModel(
    SentencePieceModel model, {
    SentencePieceConfig config = const SentencePieceConfig(),
  }) {
    return _createFromModel(model, config);
  }

  static TokenizationAlgorithm _createAlgorithm(
    SentencePieceModel model,
    SpVocabulary vocab,
  ) {
    final byteFallback = model.trainerSpec.byteFallback;

    switch (model.trainerSpec.modelType) {
      case ModelType.bpe:
        return BpeAlgorithm(vocab: vocab, byteFallback: byteFallback);
      case ModelType.unigram:
        return UnigramAlgorithm(vocab: vocab, byteFallback: byteFallback);
      default:
        throw UnsupportedError(
          'Unsupported model type: ${model.trainerSpec.modelType}',
        );
    }
  }

  /// Get current padding configuration.
  SpPaddingConfig? get padding => _paddingConfig;

  /// Get current truncation configuration.
  SpTruncationConfig? get truncation => _truncationConfig;

  /// Enable padding with the specified configuration.
  SentencePieceTokenizer enablePadding({
    SpPaddingDirection direction = SpPaddingDirection.right,
    int? length,
    int? padToMultipleOf,
  }) {
    _paddingConfig = SpPaddingConfig(
      direction: direction,
      length: length,
      padToMultipleOf: padToMultipleOf,
    );
    return this;
  }

  /// Disable padding.
  SentencePieceTokenizer noPadding() {
    _paddingConfig = null;
    return this;
  }

  /// Enable truncation with the specified configuration.
  SentencePieceTokenizer enableTruncation({
    required int maxLength,
    SpTruncationDirection direction = SpTruncationDirection.right,
  }) {
    _truncationConfig = SpTruncationConfig(
      maxLength: maxLength,
      direction: direction,
    );
    return this;
  }

  /// Disable truncation.
  SentencePieceTokenizer noTruncation() {
    _truncationConfig = null;
    return this;
  }

  /// Number of special tokens added during encoding.
  ///
  /// When [isPair] is true, calculates tokens for pair encoding:
  /// - BOS (if enabled) + EOS between sequences + EOS at end (if enabled)
  int numSpecialTokensToAdd({
    bool? addBosToken,
    bool? addEosToken,
    bool isPair = false,
  }) {
    var count = 0;
    final shouldAddBos = addBosToken ?? config.addBosToken;
    final shouldAddEos = addEosToken ?? config.addEosToken;

    if (shouldAddBos && vocab.bosId >= 0) count++;
    if (shouldAddEos && vocab.eosId >= 0) {
      count++; // EOS at end
      if (isPair) count++; // EOS between sequences for pairs
    }
    return count;
  }

  /// Encode text into token IDs.
  ///
  /// Throws [ArgumentError] if text exceeds maximum input length.
  Encoding encode(String text, {bool? addSpecialTokens}) {
    if (text.length > _kMaxInputLength) {
      throw ArgumentError(
        'Input text too long: ${text.length} characters exceeds maximum of $_kMaxInputLength',
      );
    }

    final shouldAddBos = addSpecialTokens ?? config.addBosToken;
    final shouldAddEos = addSpecialTokens ?? config.addEosToken;

    // Normalize text
    final normalized = _normalizer.normalize(text);

    // Tokenize
    final tokenIds = _algorithm.tokenize(normalized);

    // Build encoding
    final builder = EncodingBuilder();

    // Add BOS token
    if (shouldAddBos && vocab.bosId >= 0) {
      builder.addSpecialToken(
        token: vocab.bosPiece,
        id: vocab.bosId,
        typeId: 0,
      );
    }

    // Add content tokens
    var charPos = 0;
    for (final id in tokenIds) {
      final piece = vocab.idToPiece(id);
      final pieceLen = piece.length;

      builder.addToken(
        token: piece,
        id: id,
        typeId: 0,
        offset: (charPos, charPos + pieceLen),
        wordId: null,
      );

      charPos += pieceLen;
    }

    // Add EOS token
    if (shouldAddEos && vocab.eosId >= 0) {
      builder.addSpecialToken(
        token: vocab.eosPiece,
        id: vocab.eosId,
        typeId: 0,
      );
    }

    return _applyPostProcessing(builder.build());
  }

  Encoding _applyPostProcessing(Encoding encoding) {
    var result = encoding;

    if (_truncationConfig != null) {
      result = result.withTruncation(
        maxLength: _truncationConfig!.maxLength,
        truncateFromEnd:
            _truncationConfig!.direction == SpTruncationDirection.right,
      );
    }

    if (_paddingConfig != null) {
      final padOnRight = _paddingConfig!.direction == SpPaddingDirection.right;

      if (_paddingConfig!.length != null) {
        result = result.withPadding(
          targetLength: _paddingConfig!.length!,
          padTokenId: vocab.padId >= 0 ? vocab.padId : 0,
          padToken: vocab.padPiece,
          padOnRight: padOnRight,
        );
      }

      if (_paddingConfig!.padToMultipleOf != null) {
        result = result.withPaddingToMultipleOf(
          multiple: _paddingConfig!.padToMultipleOf!,
          padTokenId: vocab.padId >= 0 ? vocab.padId : 0,
          padToken: vocab.padPiece,
          padOnRight: padOnRight,
        );
      }
    }

    return result;
  }

  List<Encoding> _applyBatchPostProcessing(List<Encoding> encodings) {
    if (encodings.isEmpty) return encodings;

    var results = encodings;

    if (_truncationConfig != null) {
      results = results
          .map(
            (e) => e.withTruncation(
              maxLength: _truncationConfig!.maxLength,
              truncateFromEnd:
                  _truncationConfig!.direction == SpTruncationDirection.right,
            ),
          )
          .toList();
    }

    if (_paddingConfig != null) {
      final padOnRight = _paddingConfig!.direction == SpPaddingDirection.right;
      final padTokenId = vocab.padId >= 0 ? vocab.padId : 0;

      int targetLength;
      if (_paddingConfig!.length != null) {
        targetLength = _paddingConfig!.length!;
      } else {
        targetLength = results.map((e) => e.length).reduce((a, b) => a > b ? a : b);
      }

      if (_paddingConfig!.padToMultipleOf != null) {
        final multiple = _paddingConfig!.padToMultipleOf!;
        final remainder = targetLength % multiple;
        if (remainder != 0) {
          targetLength += multiple - remainder;
        }
      }

      results = results
          .map(
            (e) => e.withPadding(
              targetLength: targetLength,
              padTokenId: padTokenId,
              padToken: vocab.padPiece,
              padOnRight: padOnRight,
            ),
          )
          .toList();
    }

    return results;
  }

  /// Encode a pair of sequences for tasks like question answering or NLI.
  ///
  /// The first sequence gets typeId=0, second sequence gets typeId=1.
  /// Special tokens are handled according to config:
  /// - BOS token (if enabled) is added at the start
  /// - EOS token (if enabled) is added between sequences and at the end
  ///
  /// The [strategy] parameter controls how truncation is applied when the
  /// combined sequences exceed [maxLength]:
  /// - [TruncationStrategy.longestFirst]: Truncate the longer sequence first
  /// - [TruncationStrategy.onlyFirst]: Only truncate the first sequence
  /// - [TruncationStrategy.onlySecond]: Only truncate the second sequence
  /// - [TruncationStrategy.doNotTruncate]: Don't truncate (may exceed maxLength)
  Encoding encodePair(
    String text,
    String textPair, {
    bool? addSpecialTokens,
    int? maxLength,
    TruncationStrategy strategy = TruncationStrategy.longestFirst,
  }) {
    if (text.length > _kMaxInputLength) {
      throw ArgumentError(
        'First input text too long: ${text.length} characters exceeds maximum of $_kMaxInputLength',
      );
    }
    if (textPair.length > _kMaxInputLength) {
      throw ArgumentError(
        'Second input text too long: ${textPair.length} characters exceeds maximum of $_kMaxInputLength',
      );
    }

    final shouldAddBos = addSpecialTokens ?? config.addBosToken;
    final shouldAddEos = addSpecialTokens ?? config.addEosToken;

    // Calculate number of special tokens for truncation
    var numSpecialTokens = 0;
    if (shouldAddBos && vocab.bosId >= 0) numSpecialTokens++;
    if (shouldAddEos && vocab.eosId >= 0) numSpecialTokens += 2; // separator + end

    // Encode both sequences without special tokens
    final savedPadding = _paddingConfig;
    final savedTruncation = _truncationConfig;
    _paddingConfig = null;
    _truncationConfig = null;

    final encoding1 = _encodeSequence(text, typeId: 0, sequenceId: 0);
    final encoding2 = _encodeSequence(textPair, typeId: 1, sequenceId: 1);

    _paddingConfig = savedPadding;
    _truncationConfig = savedTruncation;

    // Apply pair truncation if maxLength is specified
    Encoding truncated1;
    Encoding truncated2;

    if (maxLength != null) {
      (truncated1, truncated2) = Encoding.truncatePair(
        encodingA: encoding1,
        encodingB: encoding2,
        maxLength: maxLength,
        strategy: strategy,
        numSpecialTokens: numSpecialTokens,
      );
    } else {
      truncated1 = encoding1;
      truncated2 = encoding2;
    }

    // Build final encoding with special tokens
    final builder = EncodingBuilder();

    // Add BOS token
    if (shouldAddBos && vocab.bosId >= 0) {
      builder.addSpecialToken(
        token: vocab.bosPiece,
        id: vocab.bosId,
        typeId: 0,
      );
    }

    // Add first sequence tokens
    for (var i = 0; i < truncated1.length; i++) {
      builder.addToken(
        token: truncated1.tokens[i],
        id: truncated1.ids[i],
        typeId: 0,
        offset: truncated1.offsets[i],
        wordId: truncated1.wordIds[i],
        sequenceId: 0,
      );
    }

    // Add separator EOS token (between sequences)
    if (shouldAddEos && vocab.eosId >= 0) {
      builder.addSpecialToken(
        token: vocab.eosPiece,
        id: vocab.eosId,
        typeId: 0,
      );
    }

    // Add second sequence tokens
    for (var i = 0; i < truncated2.length; i++) {
      builder.addToken(
        token: truncated2.tokens[i],
        id: truncated2.ids[i],
        typeId: 1,
        offset: truncated2.offsets[i],
        wordId: truncated2.wordIds[i],
        sequenceId: 1,
      );
    }

    // Add final EOS token
    if (shouldAddEos && vocab.eosId >= 0) {
      builder.addSpecialToken(
        token: vocab.eosPiece,
        id: vocab.eosId,
        typeId: 1,
      );
    }

    return _applyPostProcessing(builder.build());
  }

  /// Encode a sequence without special tokens, for internal use.
  Encoding _encodeSequence(String text, {required int typeId, required int sequenceId}) {
    final normalized = _normalizer.normalize(text);
    final tokenIds = _algorithm.tokenize(normalized);

    final builder = EncodingBuilder();
    var charPos = 0;

    for (final id in tokenIds) {
      final piece = vocab.idToPiece(id);
      final pieceLen = piece.length;

      builder.addToken(
        token: piece,
        id: id,
        typeId: typeId,
        offset: (charPos, charPos + pieceLen),
        wordId: null,
        sequenceId: sequenceId,
      );

      charPos += pieceLen;
    }

    return builder.build();
  }

  /// Encode multiple text pairs.
  List<Encoding> encodePairBatch(
    List<(String, String)> textPairs, {
    bool? addSpecialTokens,
    int? maxLength,
    TruncationStrategy strategy = TruncationStrategy.longestFirst,
  }) {
    final savedPadding = _paddingConfig;
    final savedTruncation = _truncationConfig;
    _paddingConfig = null;
    _truncationConfig = null;

    final encodings = textPairs
        .map((pair) => encodePair(
              pair.$1,
              pair.$2,
              addSpecialTokens: addSpecialTokens,
              maxLength: maxLength,
              strategy: strategy,
            ))
        .toList();

    _paddingConfig = savedPadding;
    _truncationConfig = savedTruncation;

    return _applyBatchPostProcessing(encodings);
  }

  /// Encode multiple texts.
  List<Encoding> encodeBatch(List<String> texts, {bool? addSpecialTokens}) {
    final savedPadding = _paddingConfig;
    final savedTruncation = _truncationConfig;
    _paddingConfig = null;
    _truncationConfig = null;

    final encodings = texts
        .map((text) => encode(text, addSpecialTokens: addSpecialTokens))
        .toList();

    _paddingConfig = savedPadding;
    _truncationConfig = savedTruncation;

    return _applyBatchPostProcessing(encodings);
  }

  /// Encode multiple texts in parallel using Isolates.
  Future<List<Encoding>> encodeBatchParallel(
    List<String> texts, {
    bool? addSpecialTokens,
    int? numWorkers,
  }) async {
    if (texts.length < _kMinBatchSizeForParallel) {
      return encodeBatch(texts, addSpecialTokens: addSpecialTokens);
    }

    final workerCount = numWorkers ?? _getOptimalWorkerCount(texts.length);
    final chunkSize = (texts.length / workerCount).ceil();

    final modelData = _SerializableModelData.fromTokenizer(this);
    final futures = <Future<List<_EncodingData>>>[];

    for (var i = 0; i < workerCount; i++) {
      final start = i * chunkSize;
      if (start >= texts.length) break;

      final end = (start + chunkSize).clamp(0, texts.length);
      final chunk = texts.sublist(start, end);

      futures.add(
        Isolate.run(
          () => _encodeChunkInIsolate(
            chunk,
            modelData,
            config,
            addSpecialTokens,
          ),
        ),
      );
    }

    final results = await Future.wait(futures);

    final encodings = <Encoding>[];
    for (final chunkResults in results) {
      for (final data in chunkResults) {
        encodings.add(data.toEncoding());
      }
    }

    return _applyBatchPostProcessing(encodings);
  }

  int _getOptimalWorkerCount(int batchSize) {
    const maxWorkers = 4;
    const minItemsPerWorker = 4;

    final workersByItems = (batchSize / minItemsPerWorker).floor();
    return workersByItems.clamp(1, maxWorkers);
  }

  /// Decode token IDs back to text.
  String decode(List<int> ids, {bool skipSpecialTokens = true}) {
    final buffer = StringBuffer();

    for (final id in ids) {
      if (skipSpecialTokens && vocab.isSpecialToken(id)) {
        continue;
      }

      final piece = vocab.idToPiece(id);

      // Handle byte tokens
      if (vocab.isByteToken(id)) {
        final byteValue = vocab.byteTokenToValue(id);
        if (byteValue != null) {
          buffer.writeCharCode(byteValue);
        }
        continue;
      }

      buffer.write(piece);
    }

    return _normalizer.denormalize(buffer.toString());
  }

  /// Decode multiple token ID sequences.
  List<String> decodeBatch(
    List<List<int>> idsBatch, {
    bool skipSpecialTokens = true,
  }) {
    return idsBatch
        .map((ids) => decode(ids, skipSpecialTokens: skipSpecialTokens))
        .toList();
  }

  /// Decode a stream of token IDs to a stream of text chunks.
  ///
  /// This is designed for LLM streaming output where tokens arrive one at a time.
  /// The decoder handles incomplete UTF-8 sequences from byte tokens by buffering
  /// until complete characters can be formed.
  ///
  /// Example:
  /// ```dart
  /// final textStream = tokenizer.decodeStream(llmTokenStream);
  /// await for (final chunk in textStream) {
  ///   stdout.write(chunk); // Display incrementally
  /// }
  /// ```
  Stream<String> decodeStream(
    Stream<int> tokenIds, {
    bool skipSpecialTokens = true,
  }) async* {
    final chunks = <String>[];
    final streamer = createTextStreamer(
      skipSpecialTokens: skipSpecialTokens,
      onFinalizedText: (text, {required streamEnd}) {
        if (text.isNotEmpty) chunks.add(text);
      },
    );

    await for (final id in tokenIds) {
      streamer.put(id);
      // Yield any chunks that were emitted
      while (chunks.isNotEmpty) {
        yield chunks.removeAt(0);
      }
    }

    // Flush remaining content
    streamer.end();
    while (chunks.isNotEmpty) {
      yield chunks.removeAt(0);
    }
  }

  /// Decode token IDs with a callback for each text chunk.
  ///
  /// This is useful when you want to process text incrementally without
  /// using streams (e.g., for direct UI updates).
  ///
  /// Example:
  /// ```dart
  /// tokenizer.decodeWithCallback(
  ///   tokenIds,
  ///   (chunk) => stdout.write(chunk),
  /// );
  /// ```
  void decodeWithCallback(
    List<int> ids,
    void Function(String chunk) onChunk, {
    bool skipSpecialTokens = true,
  }) {
    final streamer = createTextStreamer(
      skipSpecialTokens: skipSpecialTokens,
      onFinalizedText: (text, {required streamEnd}) {
        if (text.isNotEmpty) onChunk(text);
      },
    );

    for (final id in ids) {
      streamer.put(id);
    }
    streamer.end();
  }

  /// Create a TextStreamer for HuggingFace-compatible streaming.
  ///
  /// This is the recommended API for LLM token streaming, matching
  /// HuggingFace's `TextStreamer` interface with `put()` and `end()` methods.
  ///
  /// Example:
  /// ```dart
  /// final streamer = tokenizer.createTextStreamer(
  ///   onFinalizedText: (text, {required streamEnd}) => stdout.write(text),
  /// );
  /// for (final tokenId in llmOutput) {
  ///   streamer.put(tokenId);
  /// }
  /// streamer.end();
  /// ```
  ///
  /// [skipSpecialTokens] - Whether to skip special tokens like BOS/EOS.
  /// [skipPrompt] - Whether to skip the initial prompt tokens.
  /// [promptLength] - Number of prompt tokens to skip (when [skipPrompt] is true).
  /// [onFinalizedText] - Callback for finalized text chunks.
  TextStreamer createTextStreamer({
    bool skipSpecialTokens = true,
    bool skipPrompt = false,
    int promptLength = 1,
    OnFinalizedText? onFinalizedText,
  }) {
    return TextStreamer(
      this,
      skipSpecialTokens: skipSpecialTokens,
      skipPrompt: skipPrompt,
      promptLength: promptLength,
      onFinalizedText: onFinalizedText,
    );
  }

  /// Convert tokens to IDs.
  List<int> convertTokensToIds(List<String> tokens) {
    return tokens.map((t) => vocab.pieceToId(t)).toList();
  }

  /// Convert IDs to tokens.
  List<String> convertIdsToTokens(List<int> ids) {
    return ids.map((id) => vocab.idToPiece(id)).toList();
  }

  /// Get vocabulary size.
  int get vocabSize => vocab.size;

  /// Add new tokens to the vocabulary.
  ///
  /// Returns the number of tokens actually added (excluding duplicates).
  /// New tokens can be used in tokenization and will be recognized.
  ///
  /// ```dart
  /// final added = tokenizer.addTokens(['<custom>', '<domain>']);
  /// print('Added $added tokens');
  /// ```
  int addTokens(List<String> tokens) {
    return vocab.addTokens(tokens);
  }

  /// Add special tokens to the vocabulary.
  ///
  /// Special tokens are tokens that should be treated specially during
  /// encoding/decoding (e.g., skip in decode with skipSpecialTokens).
  ///
  /// Supported keys: 'pad_token', 'mask_token', 'sep_token', 'cls_token',
  /// or any custom key.
  ///
  /// ```dart
  /// tokenizer.addSpecialTokens({
  ///   'pad_token': '<pad>',
  ///   'mask_token': '<mask>',
  /// });
  /// ```
  int addSpecialTokens(Map<String, String> specialTokens) {
    var added = 0;
    for (final entry in specialTokens.entries) {
      final key = entry.key;
      final token = entry.value;

      final existingId = vocab.contains(token) ? vocab.pieceToId(token) : null;
      final id = vocab.addSpecialToken(token);

      // Update special token references
      switch (key) {
        case 'pad_token':
          vocab.padId = id;
          vocab.padPiece = token;
          break;
        case 'bos_token':
          vocab.bosId = id;
          vocab.bosPiece = token;
          break;
        case 'eos_token':
          vocab.eosId = id;
          vocab.eosPiece = token;
          break;
      }

      if (existingId == null) added++;
    }
    return added;
  }

  /// Get all dynamically added tokens.
  Map<String, int> getAddedVocab() => vocab.getAddedVocab();

  /// Check if a token was added dynamically.
  bool isAddedToken(String token) => vocab.isAddedToken(token);

  /// Get the full vocabulary as a map from token to ID.
  ///
  /// If [withAddedTokens] is false, only returns the original vocabulary.
  Map<String, int> getVocab({bool withAddedTokens = true}) {
    if (withAddedTokens) {
      return vocab.vocabularyMap;
    }
    // Filter out added tokens
    final result = <String, int>{};
    for (final entry in vocab.vocabularyMap.entries) {
      if (!vocab.isAddedToken(entry.key)) {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  /// Tokenize text into token strings without creating full Encoding.
  ///
  /// This is a lightweight alternative to [encode] when you only need
  /// the token strings.
  ///
  /// ```dart
  /// final tokens = tokenizer.tokenize('Hello world');
  /// // → ['▁Hello', '▁world']
  /// ```
  List<String> tokenize(String text) {
    if (text.isEmpty) return [];
    if (text.length > _kMaxInputLength) {
      throw ArgumentError(
        'Input text too long: ${text.length} characters exceeds maximum of $_kMaxInputLength',
      );
    }

    final normalized = _normalizer.normalize(text);
    final tokenIds = _algorithm.tokenize(normalized);

    return [for (final id in tokenIds) vocab.idToPiece(id)];
  }

  /// Tokenize multiple texts.
  List<List<String>> tokenizeBatch(List<String> texts) {
    return [for (final text in texts) tokenize(text)];
  }

  @override
  String toString() =>
      'SentencePieceTokenizer(modelType: $modelType, vocabSize: $vocabSize)';
}

/// Serializable model data for Isolate transfer.
class _SerializableModelData {
  final List<String> pieces;
  final List<double> scores;
  final List<int> types;
  final int unkId;
  final int bosId;
  final int eosId;
  final int padId;
  final String unkPiece;
  final String bosPiece;
  final String eosPiece;
  final String padPiece;
  final bool byteFallback;
  final ModelType modelType;
  final bool addDummyPrefix;
  final bool removeExtraWhitespaces;
  final bool escapeWhitespaces;

  const _SerializableModelData({
    required this.pieces,
    required this.scores,
    required this.types,
    required this.unkId,
    required this.bosId,
    required this.eosId,
    required this.padId,
    required this.unkPiece,
    required this.bosPiece,
    required this.eosPiece,
    required this.padPiece,
    required this.byteFallback,
    required this.modelType,
    required this.addDummyPrefix,
    required this.removeExtraWhitespaces,
    required this.escapeWhitespaces,
  });

  factory _SerializableModelData.fromTokenizer(SentencePieceTokenizer tokenizer) {
    return _SerializableModelData(
      pieces: tokenizer.vocab.pieces,
      scores: tokenizer.vocab.scores.toList(),
      types: List.generate(
        tokenizer.vocab.size,
        (i) => tokenizer.vocab.getType(i).value,
      ),
      unkId: tokenizer.vocab.unkId,
      bosId: tokenizer.vocab.bosId,
      eosId: tokenizer.vocab.eosId,
      padId: tokenizer.vocab.padId,
      unkPiece: tokenizer.vocab.unkPiece,
      bosPiece: tokenizer.vocab.bosPiece,
      eosPiece: tokenizer.vocab.eosPiece,
      padPiece: tokenizer.vocab.padPiece,
      byteFallback: tokenizer.vocab.hasByteFallback,
      modelType: tokenizer.modelType,
      addDummyPrefix: tokenizer._normalizer.addDummyPrefix,
      removeExtraWhitespaces: tokenizer._normalizer.removeExtraWhitespaces,
      escapeWhitespaces: tokenizer._normalizer.escapeWhitespaces,
    );
  }

  SentencePieceTokenizer recreateTokenizer(SentencePieceConfig config) {
    // Reconstruct the model
    final modelPieces = <SentencePiece>[];
    for (var i = 0; i < pieces.length; i++) {
      modelPieces.add(SentencePiece(
        piece: pieces[i],
        score: scores[i],
        type: PieceType.fromValue(types[i]),
      ));
    }

    final model = SentencePieceModel(
      pieces: modelPieces,
      trainerSpec: TrainerSpec(
        modelType: modelType,
        vocabSize: pieces.length,
        unkId: unkId,
        bosId: bosId,
        eosId: eosId,
        padId: padId,
        unkPiece: unkPiece,
        bosPiece: bosPiece,
        eosPiece: eosPiece,
        padPiece: padPiece,
        byteFallback: byteFallback,
      ),
      normalizerSpec: NormalizerSpec(
        name: 'identity',
        addDummyPrefix: addDummyPrefix,
        removeExtraWhitespaces: removeExtraWhitespaces,
        escapeWhitespaces: escapeWhitespaces,
      ),
    );

    return SentencePieceTokenizer._createFromModel(model, config);
  }
}

class _EncodingData {
  final List<String> tokens;
  final List<int> ids;
  final List<int> typeIds;
  final List<int> attentionMask;
  final List<int> specialTokensMask;
  final List<List<int>> offsets;
  final List<int?> wordIds;
  final List<int?> sequenceIds;

  const _EncodingData({
    required this.tokens,
    required this.ids,
    required this.typeIds,
    required this.attentionMask,
    required this.specialTokensMask,
    required this.offsets,
    required this.wordIds,
    required this.sequenceIds,
  });

  factory _EncodingData.fromEncoding(Encoding encoding) {
    return _EncodingData(
      tokens: encoding.tokens.toList(),
      ids: encoding.ids.toList(),
      typeIds: encoding.typeIds.toList(),
      attentionMask: encoding.attentionMask.toList(),
      specialTokensMask: encoding.specialTokensMask.toList(),
      offsets: encoding.offsets.map((o) => [o.$1, o.$2]).toList(),
      wordIds: encoding.wordIds.toList(),
      sequenceIds: encoding.sequenceIds.toList(),
    );
  }

  Encoding toEncoding() {
    return Encoding(
      tokens: tokens,
      ids: ids,
      typeIds: typeIds,
      attentionMask: attentionMask,
      specialTokensMask: specialTokensMask,
      offsets: offsets.map((o) => (o[0], o[1])).toList(),
      wordIds: wordIds,
      sequenceIds: sequenceIds,
    );
  }
}

List<_EncodingData> _encodeChunkInIsolate(
  List<String> texts,
  _SerializableModelData modelData,
  SentencePieceConfig config,
  bool? addSpecialTokens,
) {
  final tokenizer = modelData.recreateTokenizer(config);
  final results = <_EncodingData>[];

  for (final text in texts) {
    final encoding = tokenizer.encode(text, addSpecialTokens: addSpecialTokens);
    results.add(_EncodingData.fromEncoding(encoding));
  }

  return results;
}
