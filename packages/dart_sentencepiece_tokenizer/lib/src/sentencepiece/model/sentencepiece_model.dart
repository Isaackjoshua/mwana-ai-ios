import 'dart:io';
import 'dart:typed_data';

import 'model_proto.dart';
import 'protobuf_reader.dart';

/// Loads SentencePiece model files (.model).
class SentencePieceModelLoader {
  SentencePieceModelLoader._();

  static Future<SentencePieceModel> fromFile(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    return fromBytes(bytes);
  }

  static SentencePieceModel fromFileSync(String path) {
    final file = File(path);
    final bytes = file.readAsBytesSync();
    return fromBytes(bytes);
  }

  static SentencePieceModel fromBytes(Uint8List data) {
    final reader = ProtobufReader(data);
    return _parse(reader);
  }

  static SentencePieceModel _parse(ProtobufReader reader) {
    final pieces = <SentencePiece>[];
    TrainerSpec trainerSpec = const TrainerSpec();
    NormalizerSpec normalizerSpec = const NormalizerSpec();
    NormalizerSpec? denormalizerSpec;

    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;

      final (fieldNumber, wireType) = tag;

      switch (fieldNumber) {
        case 1: // pieces
          if (wireType == WireType.lengthDelimited) {
            final embedded = reader.readEmbeddedMessage();
            pieces.add(_parseSentencePiece(embedded));
          } else {
            reader.skipField(wireType);
          }
        case 2: // trainer_spec
          if (wireType == WireType.lengthDelimited) {
            final embedded = reader.readEmbeddedMessage();
            trainerSpec = _parseTrainerSpec(embedded);
          } else {
            reader.skipField(wireType);
          }
        case 3: // normalizer_spec
          if (wireType == WireType.lengthDelimited) {
            final embedded = reader.readEmbeddedMessage();
            normalizerSpec = _parseNormalizerSpec(embedded);
          } else {
            reader.skipField(wireType);
          }
        case 5: // denormalizer_spec
          if (wireType == WireType.lengthDelimited) {
            final embedded = reader.readEmbeddedMessage();
            denormalizerSpec = _parseNormalizerSpec(embedded);
          } else {
            reader.skipField(wireType);
          }
        default:
          reader.skipField(wireType);
      }
    }

    return SentencePieceModel(
      pieces: pieces,
      trainerSpec: trainerSpec,
      normalizerSpec: normalizerSpec,
      denormalizerSpec: denormalizerSpec,
    );
  }

  static SentencePiece _parseSentencePiece(ProtobufReader reader) {
    String piece = '';
    double score = 0.0;
    PieceType type = PieceType.normal;

    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;

      final (fieldNumber, wireType) = tag;

      switch (fieldNumber) {
        case 1: // piece
          if (wireType == WireType.lengthDelimited) {
            piece = reader.readString();
          } else {
            reader.skipField(wireType);
          }
        case 2: // score
          if (wireType == WireType.fixed32) {
            score = reader.readFloat();
          } else {
            reader.skipField(wireType);
          }
        case 3: // type
          if (wireType == WireType.varint) {
            type = PieceType.fromValue(reader.readVarint());
          } else {
            reader.skipField(wireType);
          }
        default:
          reader.skipField(wireType);
      }
    }

    return SentencePiece(piece: piece, score: score, type: type);
  }

  static TrainerSpec _parseTrainerSpec(ProtobufReader reader) {
    ModelType modelType = ModelType.unigram;
    int vocabSize = 8000;
    int unkId = 0;
    int bosId = 1;
    int eosId = 2;
    int padId = -1;
    String unkPiece = '<unk>';
    String bosPiece = '<s>';
    String eosPiece = '</s>';
    String padPiece = '<pad>';
    bool byteFallback = false;

    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;

      final (fieldNumber, wireType) = tag;

      switch (fieldNumber) {
        case 3: // model_type
          if (wireType == WireType.varint) {
            modelType = ModelType.fromValue(reader.readVarint());
          } else {
            reader.skipField(wireType);
          }
        case 4: // vocab_size
          if (wireType == WireType.varint) {
            vocabSize = reader.readVarint();
          } else {
            reader.skipField(wireType);
          }
        case 35: // byte_fallback
          if (wireType == WireType.varint) {
            byteFallback = reader.readBool();
          } else {
            reader.skipField(wireType);
          }
        case 40: // unk_id
          if (wireType == WireType.varint) {
            unkId = reader.readSignedVarint();
          } else {
            reader.skipField(wireType);
          }
        case 41: // bos_id
          if (wireType == WireType.varint) {
            bosId = reader.readSignedVarint();
          } else {
            reader.skipField(wireType);
          }
        case 42: // eos_id
          if (wireType == WireType.varint) {
            eosId = reader.readSignedVarint();
          } else {
            reader.skipField(wireType);
          }
        case 43: // pad_id
          if (wireType == WireType.varint) {
            padId = reader.readSignedVarint();
          } else {
            reader.skipField(wireType);
          }
        case 45: // unk_piece
          if (wireType == WireType.lengthDelimited) {
            unkPiece = reader.readString();
          } else {
            reader.skipField(wireType);
          }
        case 46: // bos_piece
          if (wireType == WireType.lengthDelimited) {
            bosPiece = reader.readString();
          } else {
            reader.skipField(wireType);
          }
        case 47: // eos_piece
          if (wireType == WireType.lengthDelimited) {
            eosPiece = reader.readString();
          } else {
            reader.skipField(wireType);
          }
        case 48: // pad_piece
          if (wireType == WireType.lengthDelimited) {
            padPiece = reader.readString();
          } else {
            reader.skipField(wireType);
          }
        default:
          reader.skipField(wireType);
      }
    }

    return TrainerSpec(
      modelType: modelType,
      vocabSize: vocabSize,
      unkId: unkId,
      bosId: bosId,
      eosId: eosId,
      padId: padId,
      unkPiece: unkPiece,
      bosPiece: bosPiece,
      eosPiece: eosPiece,
      padPiece: padPiece,
      byteFallback: byteFallback,
    );
  }

  static NormalizerSpec _parseNormalizerSpec(ProtobufReader reader) {
    String name = '';
    Uint8List? precompiledCharsmap;
    bool addDummyPrefix = true;
    bool removeExtraWhitespaces = true;
    bool escapeWhitespaces = true;

    while (reader.hasMore) {
      final tag = reader.readTag();
      if (tag == null) break;

      final (fieldNumber, wireType) = tag;

      switch (fieldNumber) {
        case 1: // name
          if (wireType == WireType.lengthDelimited) {
            name = reader.readString();
          } else {
            reader.skipField(wireType);
          }
        case 2: // precompiled_charsmap
          if (wireType == WireType.lengthDelimited) {
            precompiledCharsmap = reader.readBytes();
          } else {
            reader.skipField(wireType);
          }
        case 3: // add_dummy_prefix
          if (wireType == WireType.varint) {
            addDummyPrefix = reader.readBool();
          } else {
            reader.skipField(wireType);
          }
        case 4: // remove_extra_whitespaces
          if (wireType == WireType.varint) {
            removeExtraWhitespaces = reader.readBool();
          } else {
            reader.skipField(wireType);
          }
        case 5: // escape_whitespaces
          if (wireType == WireType.varint) {
            escapeWhitespaces = reader.readBool();
          } else {
            reader.skipField(wireType);
          }
        default:
          reader.skipField(wireType);
      }
    }

    return NormalizerSpec(
      name: name,
      precompiledCharsmap: precompiledCharsmap,
      addDummyPrefix: addDummyPrefix,
      removeExtraWhitespaces: removeExtraWhitespaces,
      escapeWhitespaces: escapeWhitespaces,
    );
  }
}
