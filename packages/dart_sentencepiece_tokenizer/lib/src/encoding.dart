import 'dart:typed_data';

enum TruncationStrategy { longestFirst, onlyFirst, onlySecond, doNotTruncate }

class Encoding {
  final List<String> tokens;
  final Int32List ids;
  final Uint8List typeIds;
  final Uint8List attentionMask;
  final Uint8List specialTokensMask;
  final List<(int, int)> offsets;
  final List<int?> wordIds;
  final List<int?>? _sequenceIds;
  List<int?>? _cachedSequenceIds;

  Encoding({
    required this.tokens,
    required List<int> ids,
    required List<int> typeIds,
    required List<int> attentionMask,
    required List<int> specialTokensMask,
    required this.offsets,
    required this.wordIds,
    List<int?>? sequenceIds,
  }) : ids = ids is Int32List ? ids : Int32List.fromList(ids),
       typeIds = typeIds is Uint8List ? typeIds : Uint8List.fromList(typeIds),
       attentionMask = attentionMask is Uint8List
           ? attentionMask
           : Uint8List.fromList(attentionMask),
       specialTokensMask = specialTokensMask is Uint8List
           ? specialTokensMask
           : Uint8List.fromList(specialTokensMask),
       _sequenceIds = sequenceIds;

  Encoding._typed({
    required this.tokens,
    required this.ids,
    required this.typeIds,
    required this.attentionMask,
    required this.specialTokensMask,
    required this.offsets,
    required this.wordIds,
    List<int?>? sequenceIds,
  }) : _sequenceIds = sequenceIds;

  int get length => tokens.length;

  bool get isEmpty => tokens.isEmpty;

  bool get isNotEmpty => tokens.isNotEmpty;

  List<int?> get sequenceIds {
    if (_sequenceIds != null) return _sequenceIds;

    return _cachedSequenceIds ??= List.generate(length, (i) {
      if (specialTokensMask[i] == 1) return null;
      return typeIds[i];
    });
  }

  int get nSequences {
    final seqIds = sequenceIds;
    if (seqIds.any((id) => id == 1)) return 2;
    if (seqIds.any((id) => id == 0)) return 1;
    return 0;
  }

  int? charToToken(int charPos, {int sequenceIndex = 0}) {
    final seqIds = sequenceIds;
    for (var i = 0; i < length; i++) {
      if (seqIds[i] != sequenceIndex) continue;
      final (start, end) = offsets[i];
      if (charPos >= start && charPos < end) {
        return i;
      }
    }
    return null;
  }

  int? charToWord(int charPos, {int sequenceIndex = 0}) {
    final tokenIdx = charToToken(charPos, sequenceIndex: sequenceIndex);
    if (tokenIdx == null) return null;
    return wordIds[tokenIdx];
  }

  (int, int)? tokenToChars(int tokenIndex) {
    if (tokenIndex < 0 || tokenIndex >= length) return null;
    final offset = offsets[tokenIndex];
    if (offset == (0, 0) && specialTokensMask[tokenIndex] == 1) return null;
    return offset;
  }

  int? tokenToWord(int tokenIndex) {
    if (tokenIndex < 0 || tokenIndex >= length) return null;
    return wordIds[tokenIndex];
  }

  int? tokenToSequence(int tokenIndex) {
    if (tokenIndex < 0 || tokenIndex >= length) return null;
    return sequenceIds[tokenIndex];
  }

  (int, int)? wordToChars(int wordIndex, {int sequenceIndex = 0}) {
    final seqIds = sequenceIds;
    int? start;
    int? end;

    for (var i = 0; i < length; i++) {
      if (seqIds[i] != sequenceIndex) continue;
      if (wordIds[i] != wordIndex) continue;

      final (tStart, tEnd) = offsets[i];
      if (start == null || tStart < start) start = tStart;
      if (end == null || tEnd > end) end = tEnd;
    }

    if (start == null || end == null) return null;
    return (start, end);
  }

  (int, int)? wordToTokens(int wordIndex, {int sequenceIndex = 0}) {
    final seqIds = sequenceIds;
    int? start;
    int? end;

    for (var i = 0; i < length; i++) {
      if (seqIds[i] != sequenceIndex) continue;
      if (wordIds[i] != wordIndex) continue;

      start ??= i;
      end = i + 1;
    }

    if (start == null || end == null) return null;
    return (start, end);
  }

  factory Encoding.empty() => Encoding._typed(
    tokens: const [],
    ids: Int32List(0),
    typeIds: Uint8List(0),
    attentionMask: Uint8List(0),
    specialTokensMask: Uint8List(0),
    offsets: const [],
    wordIds: const [],
    sequenceIds: const [],
  );

  static Encoding merge(
    List<Encoding> encodings, {
    bool growingOffsets = true,
  }) {
    if (encodings.isEmpty) return Encoding.empty();
    if (encodings.length == 1) return encodings.first;

    var totalLength = 0;
    for (final enc in encodings) {
      totalLength += enc.length;
    }

    final tokens = <String>[];
    final ids = Int32List(totalLength);
    final typeIds = Uint8List(totalLength);
    final attentionMask = Uint8List(totalLength);
    final specialTokensMask = Uint8List(totalLength);
    final offsets = <(int, int)>[];
    final wordIds = <int?>[];
    final sequenceIds = <int?>[];

    var offsetShift = 0;
    var wordIdShift = 0;
    var destIndex = 0;

    for (var encIdx = 0; encIdx < encodings.length; encIdx++) {
      final enc = encodings[encIdx];

      tokens.addAll(enc.tokens);

      ids.setRange(destIndex, destIndex + enc.length, enc.ids);
      typeIds.setRange(destIndex, destIndex + enc.length, enc.typeIds);
      attentionMask.setRange(
        destIndex,
        destIndex + enc.length,
        enc.attentionMask,
      );
      specialTokensMask.setRange(
        destIndex,
        destIndex + enc.length,
        enc.specialTokensMask,
      );

      if (growingOffsets) {
        for (final (start, end) in enc.offsets) {
          if (start == 0 && end == 0) {
            offsets.add((0, 0));
          } else {
            offsets.add((start + offsetShift, end + offsetShift));
          }
        }
        final maxEnd = enc.offsets
            .where((o) => o != (0, 0))
            .fold<int>(0, (max, o) => o.$2 > max ? o.$2 : max);
        offsetShift += maxEnd;
      } else {
        offsets.addAll(enc.offsets);
      }

      for (final wid in enc.wordIds) {
        if (wid == null) {
          wordIds.add(null);
        } else {
          wordIds.add(wid + wordIdShift);
        }
      }
      final maxWordId = enc.wordIds
          .where((w) => w != null)
          .fold<int>(0, (max, w) => w! > max ? w : max);
      wordIdShift += maxWordId + 1;

      sequenceIds.addAll(enc.sequenceIds);
      destIndex += enc.length;
    }

    return Encoding._typed(
      tokens: tokens,
      ids: ids,
      typeIds: typeIds,
      attentionMask: attentionMask,
      specialTokensMask: specialTokensMask,
      offsets: offsets,
      wordIds: wordIds,
      sequenceIds: sequenceIds,
    );
  }

  Encoding withPadding({
    required int targetLength,
    required int padTokenId,
    String padToken = '[PAD]',
    bool padOnRight = true,
  }) {
    if (length >= targetLength) {
      return this;
    }

    final srcLen = length;
    final dstOffset = padOnRight ? 0 : targetLength - srcLen;

    final paddedTokens = List<String>.filled(targetLength, padToken);
    paddedTokens.setRange(dstOffset, dstOffset + srcLen, tokens);

    final paddedIds = Int32List(targetLength);
    paddedIds.fillRange(0, targetLength, padTokenId);
    paddedIds.setRange(dstOffset, dstOffset + srcLen, ids);

    final paddedTypeIds = Uint8List(targetLength);
    paddedTypeIds.setRange(dstOffset, dstOffset + srcLen, typeIds);

    final paddedAttentionMask = Uint8List(targetLength);
    paddedAttentionMask.setRange(dstOffset, dstOffset + srcLen, attentionMask);

    final paddedSpecialTokensMask = Uint8List(targetLength);
    paddedSpecialTokensMask.fillRange(0, targetLength, 1);
    paddedSpecialTokensMask.setRange(
      dstOffset,
      dstOffset + srcLen,
      specialTokensMask,
    );

    final paddedOffsets = List<(int, int)>.filled(targetLength, (0, 0));
    paddedOffsets.setRange(dstOffset, dstOffset + srcLen, offsets);

    final paddedWordIds = List<int?>.filled(targetLength, null);
    paddedWordIds.setRange(dstOffset, dstOffset + srcLen, wordIds);

    final paddedSequenceIds = List<int?>.filled(targetLength, null);
    paddedSequenceIds.setRange(dstOffset, dstOffset + srcLen, sequenceIds);

    return Encoding._typed(
      tokens: paddedTokens,
      ids: paddedIds,
      typeIds: paddedTypeIds,
      attentionMask: paddedAttentionMask,
      specialTokensMask: paddedSpecialTokensMask,
      offsets: paddedOffsets,
      wordIds: paddedWordIds,
      sequenceIds: paddedSequenceIds,
    );
  }

  Encoding withPaddingToMultipleOf({
    required int multiple,
    required int padTokenId,
    String padToken = '[PAD]',
    bool padOnRight = true,
  }) {
    if (multiple <= 0) return this;

    final remainder = length % multiple;
    if (remainder == 0) return this;

    final targetLength = length + (multiple - remainder);
    return withPadding(
      targetLength: targetLength,
      padTokenId: padTokenId,
      padToken: padToken,
      padOnRight: padOnRight,
    );
  }

  Encoding withTruncation({
    required int maxLength,
    bool truncateFromEnd = true,
  }) {
    if (length <= maxLength) {
      return this;
    }

    final seqIds = sequenceIds;

    if (truncateFromEnd) {
      return Encoding._typed(
        tokens: tokens.sublist(0, maxLength),
        ids: ids.sublist(0, maxLength),
        typeIds: typeIds.sublist(0, maxLength),
        attentionMask: attentionMask.sublist(0, maxLength),
        specialTokensMask: specialTokensMask.sublist(0, maxLength),
        offsets: offsets.sublist(0, maxLength),
        wordIds: wordIds.sublist(0, maxLength),
        sequenceIds: seqIds.sublist(0, maxLength),
      );
    } else {
      final start = length - maxLength;
      return Encoding._typed(
        tokens: tokens.sublist(start),
        ids: ids.sublist(start),
        typeIds: typeIds.sublist(start),
        attentionMask: attentionMask.sublist(start),
        specialTokensMask: specialTokensMask.sublist(start),
        offsets: offsets.sublist(start),
        wordIds: wordIds.sublist(start),
        sequenceIds: seqIds.sublist(start),
      );
    }
  }

  Map<String, dynamic> toMap() => {
    'tokens': tokens,
    'ids': ids,
    'type_ids': typeIds,
    'attention_mask': attentionMask,
    'special_tokens_mask': specialTokensMask,
    'offsets': offsets.map((e) => [e.$1, e.$2]).toList(),
    'word_ids': wordIds,
    'sequence_ids': sequenceIds,
  };

  @override
  String toString() =>
      'Encoding(tokens: $tokens, ids: $ids, nSequences: $nSequences)';

  static (Encoding, Encoding) truncatePair({
    required Encoding encodingA,
    required Encoding encodingB,
    required int maxLength,
    TruncationStrategy strategy = TruncationStrategy.longestFirst,
    int numSpecialTokens = 3,
  }) {
    final availableLength = maxLength - numSpecialTokens;
    if (availableLength <= 0) {
      return (Encoding.empty(), Encoding.empty());
    }

    final totalLength = encodingA.length + encodingB.length;
    if (totalLength <= availableLength) {
      return (encodingA, encodingB);
    }

    final tokensToRemove = totalLength - availableLength;

    switch (strategy) {
      case TruncationStrategy.longestFirst:
        return _truncateLongestFirst(encodingA, encodingB, tokensToRemove);

      case TruncationStrategy.onlyFirst:
        final newLengthA = encodingA.length - tokensToRemove;
        if (newLengthA <= 0) {
          return (Encoding.empty(), encodingB);
        }
        return (encodingA.withTruncation(maxLength: newLengthA), encodingB);

      case TruncationStrategy.onlySecond:
        final newLengthB = encodingB.length - tokensToRemove;
        if (newLengthB <= 0) {
          return (encodingA, Encoding.empty());
        }
        return (encodingA, encodingB.withTruncation(maxLength: newLengthB));

      case TruncationStrategy.doNotTruncate:
        return (encodingA, encodingB);
    }
  }

  static (Encoding, Encoding) _truncateLongestFirst(
    Encoding encodingA,
    Encoding encodingB,
    int tokensToRemove,
  ) {
    var lengthA = encodingA.length;
    var lengthB = encodingB.length;

    for (var i = 0; i < tokensToRemove; i++) {
      if (lengthA > lengthB) {
        lengthA--;
      } else {
        lengthB--;
      }
    }

    final truncatedA = lengthA < encodingA.length
        ? encodingA.withTruncation(maxLength: lengthA)
        : encodingA;
    final truncatedB = lengthB < encodingB.length
        ? encodingB.withTruncation(maxLength: lengthB)
        : encodingB;

    return (truncatedA, truncatedB);
  }
}

class EncodingBuilder {
  final List<String> _tokens = [];
  final List<int> _ids = [];
  final List<int> _typeIds = [];
  final List<int> _attentionMask = [];
  final List<int> _specialTokensMask = [];
  final List<(int, int)> _offsets = [];
  final List<int?> _wordIds = [];
  final List<int?> _sequenceIds = [];

  void addToken({
    required String token,
    required int id,
    required int typeId,
    required (int, int) offset,
    int? wordId,
    int? sequenceId,
  }) {
    _tokens.add(token);
    _ids.add(id);
    _typeIds.add(typeId);
    _attentionMask.add(1);
    _specialTokensMask.add(0);
    _offsets.add(offset);
    _wordIds.add(wordId);
    _sequenceIds.add(sequenceId ?? typeId);
  }

  void addSpecialToken({
    required String token,
    required int id,
    required int typeId,
  }) {
    _tokens.add(token);
    _ids.add(id);
    _typeIds.add(typeId);
    _attentionMask.add(1);
    _specialTokensMask.add(1);
    _offsets.add((0, 0));
    _wordIds.add(null);
    _sequenceIds.add(null);
  }

  Encoding build() => Encoding._typed(
    tokens: List.unmodifiable(_tokens),
    ids: Int32List.fromList(_ids),
    typeIds: Uint8List.fromList(_typeIds),
    attentionMask: Uint8List.fromList(_attentionMask),
    specialTokensMask: Uint8List.fromList(_specialTokensMask),
    offsets: List.unmodifiable(_offsets),
    wordIds: List.unmodifiable(_wordIds),
    sequenceIds: List.unmodifiable(_sequenceIds),
  );

  void clear() {
    _tokens.clear();
    _ids.clear();
    _typeIds.clear();
    _attentionMask.clear();
    _specialTokensMask.clear();
    _offsets.clear();
    _wordIds.clear();
    _sequenceIds.clear();
  }
}
