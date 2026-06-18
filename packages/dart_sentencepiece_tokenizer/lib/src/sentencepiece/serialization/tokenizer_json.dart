import 'dart:convert';
import 'dart:io';

import '../model/model_proto.dart';
import '../sentencepiece_tokenizer.dart';

/// JSON schema version for tokenizer serialization.
const String kTokenizerJsonVersion = '1.0';

/// JSON serialization extension for SentencePieceTokenizer.
extension SentencePieceTokenizerJson on SentencePieceTokenizer {
  /// Serialize tokenizer to JSON string.
  ///
  /// The JSON format includes:
  /// - version: Schema version for compatibility
  /// - model_type: BPE or Unigram
  /// - vocab: pieces, scores, types
  /// - special_tokens: unk, bos, eos, pad
  /// - normalizer: normalization settings
  /// - config: tokenizer configuration
  String toJson({bool pretty = false}) {
    final data = _toJsonMap();
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(data);
    }
    return jsonEncode(data);
  }

  /// Save tokenizer to JSON file asynchronously.
  Future<void> saveToJson(String path, {bool pretty = true}) async {
    final json = toJson(pretty: pretty);
    await File(path).writeAsString(json);
  }

  /// Save tokenizer to JSON file synchronously.
  void saveToJsonSync(String path, {bool pretty = true}) {
    final json = toJson(pretty: pretty);
    File(path).writeAsStringSync(json);
  }

  Map<String, dynamic> _toJsonMap() {
    return {
      'version': kTokenizerJsonVersion,
      'model_type': modelType.name,
      'vocab': {
        'pieces': vocab.pieces,
        'scores': vocab.scores.toList(),
        'types': List.generate(vocab.size, (i) => vocab.getType(i).value),
      },
      'special_tokens': {
        'unk': {'id': vocab.unkId, 'piece': vocab.unkPiece},
        'bos': {'id': vocab.bosId, 'piece': vocab.bosPiece},
        'eos': {'id': vocab.eosId, 'piece': vocab.eosPiece},
        'pad': {'id': vocab.padId, 'piece': vocab.padPiece},
      },
      'normalizer': {
        'add_dummy_prefix': normalizer.addDummyPrefix,
        'remove_extra_whitespaces': normalizer.removeExtraWhitespaces,
        'escape_whitespaces': normalizer.escapeWhitespaces,
      },
      'config': {
        'add_bos_token': config.addBosToken,
        'add_eos_token': config.addEosToken,
      },
      'byte_fallback': vocab.hasByteFallback,
    };
  }

}

/// JSON deserialization for SentencePieceTokenizer.
class TokenizerJsonLoader {
  TokenizerJsonLoader._();

  /// Create tokenizer from JSON string.
  static SentencePieceTokenizer fromJsonString(
    String json, {
    SentencePieceConfig? config,
  }) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    return _fromJsonMap(data, config);
  }

  /// Load tokenizer from JSON file asynchronously.
  static Future<SentencePieceTokenizer> fromJsonFile(
    String path, {
    SentencePieceConfig? config,
  }) async {
    final json = await File(path).readAsString();
    return fromJsonString(json, config: config);
  }

  /// Load tokenizer from JSON file synchronously.
  static SentencePieceTokenizer fromJsonFileSync(
    String path, {
    SentencePieceConfig? config,
  }) {
    final json = File(path).readAsStringSync();
    return fromJsonString(json, config: config);
  }

  static SentencePieceTokenizer _fromJsonMap(
    Map<String, dynamic> data,
    SentencePieceConfig? config,
  ) {
    // Validate version
    final version = data['version'] as String?;
    if (version == null) {
      throw const FormatException('Missing version in tokenizer JSON');
    }

    // Parse model type
    final modelTypeStr = data['model_type'] as String?;
    if (modelTypeStr == null) {
      throw const FormatException('Missing model_type in tokenizer JSON');
    }
    final modelType = ModelType.values.firstWhere(
      (t) => t.name == modelTypeStr,
      orElse: () => ModelType.unigram,
    );

    // Parse vocabulary
    final vocabData = data['vocab'] as Map<String, dynamic>?;
    if (vocabData == null) {
      throw const FormatException('Missing vocab in tokenizer JSON');
    }
    final rawPieces = vocabData['pieces'] as List?;
    final rawScores = vocabData['scores'] as List?;
    final rawTypes = vocabData['types'] as List?;
    if (rawPieces == null || rawScores == null || rawTypes == null) {
      throw const FormatException(
        'Missing vocab fields (pieces, scores, types) in tokenizer JSON',
      );
    }
    final pieces = rawPieces.cast<String>();
    final scores = rawScores.cast<num>().map((n) => n.toDouble()).toList();
    final types = rawTypes.cast<int>();

    if (pieces.length != scores.length || pieces.length != types.length) {
      throw FormatException(
        'Vocab arrays have inconsistent lengths: '
        'pieces=${pieces.length}, scores=${scores.length}, types=${types.length}',
      );
    }

    // Parse special tokens
    final specialTokens = data['special_tokens'] as Map<String, dynamic>?;
    if (specialTokens == null) {
      throw const FormatException('Missing special_tokens in tokenizer JSON');
    }
    final unkData = specialTokens['unk'] as Map<String, dynamic>?;
    final bosData = specialTokens['bos'] as Map<String, dynamic>?;
    final eosData = specialTokens['eos'] as Map<String, dynamic>?;
    final padData = specialTokens['pad'] as Map<String, dynamic>?;
    if (unkData == null || bosData == null || eosData == null || padData == null) {
      throw const FormatException(
        'Missing special token entries (unk, bos, eos, pad) in tokenizer JSON',
      );
    }

    // Parse normalizer settings
    final normalizerData = data['normalizer'] as Map<String, dynamic>;
    final addDummyPrefix = normalizerData['add_dummy_prefix'] as bool? ?? true;
    final removeExtraWhitespaces = normalizerData['remove_extra_whitespaces'] as bool? ?? true;
    final escapeWhitespaces = normalizerData['escape_whitespaces'] as bool? ?? true;

    // Parse byte fallback
    final byteFallback = data['byte_fallback'] as bool? ?? false;

    // Parse config (if not overridden)
    SentencePieceConfig finalConfig;
    if (config != null) {
      finalConfig = config;
    } else {
      final configData = data['config'] as Map<String, dynamic>?;
      if (configData != null) {
        finalConfig = SentencePieceConfig(
          addBosToken: configData['add_bos_token'] as bool? ?? false,
          addEosToken: configData['add_eos_token'] as bool? ?? false,
        );
      } else {
        finalConfig = const SentencePieceConfig();
      }
    }

    // Build model pieces
    final modelPieces = <SentencePiece>[];
    for (var i = 0; i < pieces.length; i++) {
      modelPieces.add(SentencePiece(
        piece: pieces[i],
        score: scores[i],
        type: PieceType.fromValue(types[i]),
      ));
    }

    // Create model
    final model = SentencePieceModel(
      pieces: modelPieces,
      trainerSpec: TrainerSpec(
        modelType: modelType,
        vocabSize: pieces.length,
        unkId: unkData['id'] as int,
        bosId: bosData['id'] as int,
        eosId: eosData['id'] as int,
        padId: padData['id'] as int,
        unkPiece: unkData['piece'] as String,
        bosPiece: bosData['piece'] as String,
        eosPiece: eosData['piece'] as String,
        padPiece: padData['piece'] as String,
        byteFallback: byteFallback,
      ),
      normalizerSpec: NormalizerSpec(
        name: 'identity',
        addDummyPrefix: addDummyPrefix,
        removeExtraWhitespaces: removeExtraWhitespaces,
        escapeWhitespaces: escapeWhitespaces,
      ),
    );

    // Create tokenizer using internal factory
    return SentencePieceTokenizer.fromModel(model, config: finalConfig);
  }
}
