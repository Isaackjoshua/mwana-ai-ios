import 'dart:typed_data';

import '../../trie.dart';
import '../model/model_proto.dart';

class SpVocabulary {
  final Map<String, int> _pieceToId;
  final List<String> _idToPiece;
  Float32List _scores;
  Uint8List _types;
  final Trie _trie;
  final Int16List? _byteToId;

  final int unkId;
  int bosId;
  int eosId;
  int padId;
  final String unkPiece;
  String bosPiece;
  String eosPiece;
  String padPiece;

  /// Tracks IDs of tokens added after initial vocab creation.
  final Set<int> _addedTokenIds = {};

  /// Tracks IDs of special tokens added dynamically.
  final Set<int> _addedSpecialTokenIds = {};

  SpVocabulary._({
    required Map<String, int> pieceToId,
    required List<String> idToPiece,
    required Float32List scores,
    required Uint8List types,
    required Trie trie,
    Int16List? byteToId,
    required this.unkId,
    required this.bosId,
    required this.eosId,
    required this.padId,
    required this.unkPiece,
    required this.bosPiece,
    required this.eosPiece,
    required this.padPiece,
  })  : _pieceToId = pieceToId,
        _idToPiece = idToPiece,
        _scores = scores,
        _types = types,
        _trie = trie,
        _byteToId = byteToId;

  factory SpVocabulary.fromModel(SentencePieceModel model) {
    final pieces = model.pieces;
    final spec = model.trainerSpec;
    final size = pieces.length;

    final pieceToId = <String, int>{};
    // Use growable list to allow dynamic token addition
    final idToPiece = List<String>.generate(size, (_) => '', growable: true);
    final scores = Float32List(size);
    final types = Uint8List(size);
    final trie = Trie();

    Int16List? byteToId;
    if (spec.byteFallback) {
      byteToId = Int16List(256);
      for (var i = 0; i < 256; i++) {
        byteToId[i] = -1;
      }
    }

    for (var i = 0; i < size; i++) {
      final piece = pieces[i];
      final text = piece.piece;

      pieceToId[text] = i;
      idToPiece[i] = text;
      scores[i] = piece.score;
      types[i] = piece.type.value;

      // Add to trie for prefix matching
      trie.insert(text, i);

      // Track byte fallback tokens
      if (byteToId != null && piece.isByte) {
        final byteValue = _extractByteValue(text);
        if (byteValue != null) {
          byteToId[byteValue] = i;
        }
      }
    }

    return SpVocabulary._(
      pieceToId: pieceToId,
      idToPiece: idToPiece,
      scores: scores,
      types: types,
      trie: trie,
      byteToId: byteToId,
      unkId: spec.unkId,
      bosId: spec.bosId,
      eosId: spec.eosId,
      padId: spec.padId,
      unkPiece: spec.unkPiece,
      bosPiece: spec.bosPiece,
      eosPiece: spec.eosPiece,
      padPiece: spec.padPiece,
    );
  }

  int get size => _idToPiece.length;

  Trie get trie => _trie;

  bool get hasByteFallback => _byteToId != null;

  int pieceToId(String piece) {
    return _pieceToId[piece] ?? unkId;
  }

  String idToPiece(int id) {
    if (id < 0 || id >= _idToPiece.length) {
      return unkPiece;
    }
    return _idToPiece[id];
  }

  double getScore(int id) {
    if (id < 0 || id >= _scores.length) {
      return double.negativeInfinity;
    }
    return _scores[id];
  }

  PieceType getType(int id) {
    if (id < 0 || id >= _types.length) {
      return PieceType.unknown;
    }
    return PieceType.fromValue(_types[id]);
  }

  bool contains(String piece) => _pieceToId.containsKey(piece);

  bool isUnk(int id) => id == unkId;
  bool isBos(int id) => id == bosId;
  bool isEos(int id) => id == eosId;
  bool isPad(int id) => id == padId;

  bool isSpecialToken(int id) {
    final type = getType(id);
    return type == PieceType.control || type == PieceType.unknown;
  }

  bool isByteToken(int id) {
    return getType(id) == PieceType.byte;
  }

  int? byteTokenToValue(int id) {
    if (!isByteToken(id)) return null;
    return _extractByteValue(idToPiece(id));
  }

  int? valueToByteToken(int byteValue) {
    if (_byteToId == null) return null;
    if (byteValue < 0 || byteValue > 255) return null;
    final id = _byteToId[byteValue];
    return id >= 0 ? id : null;
  }

  TrieMatch? findLongestPrefix(String text, [int startIndex = 0]) {
    return _trie.findLongestPrefix(text, startIndex);
  }

  List<TrieMatch> findAllPrefixes(String text, [int startIndex = 0]) {
    return _trie.findAllPrefixes(text, startIndex);
  }

  List<String> get pieces => List.unmodifiable(_idToPiece);

  Float32List get scores => _scores;

  /// Returns an unmodifiable map of token pieces to their IDs.
  Map<String, int> get vocabularyMap => Map.unmodifiable(_pieceToId);

  static int? _extractByteValue(String piece) {
    // Format: <0xHH>
    if (piece.length != 6) return null;
    if (!piece.startsWith('<0x') || !piece.endsWith('>')) return null;
    return int.tryParse(piece.substring(3, 5), radix: 16);
  }

  /// Add new tokens to the vocabulary.
  ///
  /// Returns the number of tokens actually added (excluding duplicates).
  int addTokens(List<String> tokens, {double score = 0.0}) {
    // Filter duplicates first to enable batch allocation
    final newTokens = <String>[];
    for (final token in tokens) {
      if (!_pieceToId.containsKey(token)) {
        newTokens.add(token);
      }
    }
    if (newTokens.isEmpty) return 0;

    // Batch-expand typed arrays once
    final oldSize = _scores.length;
    final newSize = oldSize + newTokens.length;
    final expandedScores = Float32List(newSize);
    expandedScores.setRange(0, oldSize, _scores);
    final expandedTypes = Uint8List(newSize);
    expandedTypes.setRange(0, oldSize, _types);

    for (var i = 0; i < newTokens.length; i++) {
      final token = newTokens[i];
      final id = oldSize + i;
      _pieceToId[token] = id;
      _idToPiece.add(token);
      expandedScores[id] = score;
      expandedTypes[id] = PieceType.userDefined.value;
      _trie.insert(token, id);
      _addedTokenIds.add(id);
    }

    _scores = expandedScores;
    _types = expandedTypes;
    return newTokens.length;
  }

  /// Add a special token to the vocabulary.
  ///
  /// If the token already exists, it will be marked as special.
  /// Returns the ID of the token.
  int addSpecialToken(String token, {double score = 0.0}) {
    int id;
    if (_pieceToId.containsKey(token)) {
      id = _pieceToId[token]!;
    } else {
      id = _idToPiece.length;
      _pieceToId[token] = id;
      _idToPiece.add(token);
      _scores = _expandFloat32List(_scores, score);
      _types = _expandUint8List(_types, PieceType.control.value);
      _trie.insert(token, id);
      _addedTokenIds.add(id);
    }
    _addedSpecialTokenIds.add(id);
    return id;
  }

  /// Get all dynamically added tokens.
  Map<String, int> getAddedVocab() {
    final result = <String, int>{};
    for (final id in _addedTokenIds) {
      result[_idToPiece[id]] = id;
    }
    return result;
  }

  /// Check if a token was added dynamically.
  bool isAddedToken(String token) {
    final id = _pieceToId[token];
    return id != null && _addedTokenIds.contains(id);
  }

  /// Check if an ID corresponds to a dynamically added token.
  bool isAddedTokenId(int id) => _addedTokenIds.contains(id);

  /// Check if an ID corresponds to a dynamically added special token.
  bool isAddedSpecialTokenId(int id) => _addedSpecialTokenIds.contains(id);

  Float32List _expandFloat32List(Float32List original, double newValue) {
    final expanded = Float32List(original.length + 1);
    expanded.setRange(0, original.length, original);
    expanded[original.length] = newValue;
    return expanded;
  }

  Uint8List _expandUint8List(Uint8List original, int newValue) {
    final expanded = Uint8List(original.length + 1);
    expanded.setRange(0, original.length, original);
    expanded[original.length] = newValue;
    return expanded;
  }

  @override
  String toString() => 'SpVocabulary(size: $size)';
}
