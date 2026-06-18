import 'dart:convert';
import 'dart:typed_data';

/// Wire types in Protocol Buffers encoding.
class WireType {
  static const int varint = 0;
  static const int fixed64 = 1;
  static const int lengthDelimited = 2;
  static const int startGroup = 3;
  static const int endGroup = 4;
  static const int fixed32 = 5;
}

/// Minimal Protocol Buffers wire format reader for SentencePiece models.
class ProtobufReader {
  final Uint8List _data;
  int _position = 0;

  ProtobufReader(this._data);

  factory ProtobufReader.fromBytes(Uint8List data) => ProtobufReader(data);

  int get position => _position;
  int get length => _data.length;
  bool get hasMore => _position < _data.length;
  int get remaining => _data.length - _position;

  (int fieldNumber, int wireType)? readTag() {
    if (!hasMore) return null;

    final tag = readVarint();
    final wireType = tag & 0x07;
    final fieldNumber = tag >> 3;

    return (fieldNumber, wireType);
  }

  int readVarint() {
    var result = 0;
    var shift = 0;

    while (true) {
      if (_position >= _data.length) {
        throw StateError('Unexpected end of data while reading varint');
      }

      final byte = _data[_position++];
      result |= (byte & 0x7F) << shift;

      if ((byte & 0x80) == 0) {
        break;
      }

      shift += 7;
      if (shift >= 64) {
        throw StateError('Varint too long');
      }
    }

    return result;
  }

  int readSignedVarint() {
    final value = readVarint();
    return (value >> 1) ^ -(value & 1);
  }

  int readFixed32() {
    if (_position + 4 > _data.length) {
      throw StateError('Unexpected end of data while reading fixed32');
    }

    final value = _data[_position] |
        (_data[_position + 1] << 8) |
        (_data[_position + 2] << 16) |
        (_data[_position + 3] << 24);
    _position += 4;

    return value;
  }

  int readFixed64() {
    if (_position + 8 > _data.length) {
      throw StateError('Unexpected end of data while reading fixed64');
    }

    final low = readFixed32();
    final high = readFixed32();

    return (high << 32) | (low & 0xFFFFFFFF);
  }

  double readFloat() {
    if (_position + 4 > _data.length) {
      throw StateError('Unexpected end of data while reading float');
    }

    final bytes = ByteData.sublistView(_data, _position, _position + 4);
    _position += 4;

    return bytes.getFloat32(0, Endian.little);
  }

  double readDouble() {
    if (_position + 8 > _data.length) {
      throw StateError('Unexpected end of data while reading double');
    }

    final bytes = ByteData.sublistView(_data, _position, _position + 8);
    _position += 8;

    return bytes.getFloat64(0, Endian.little);
  }

  Uint8List readBytes() {
    final length = readVarint();
    if (_position + length > _data.length) {
      throw StateError(
          'Unexpected end of data while reading bytes (need $length, have ${_data.length - _position})');
    }

    final bytes = Uint8List.sublistView(_data, _position, _position + length);
    _position += length;

    return bytes;
  }

  String readString() {
    final bytes = readBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  bool readBool() => readVarint() != 0;

  ProtobufReader readEmbeddedMessage() {
    final bytes = readBytes();
    return ProtobufReader(bytes);
  }

  void skipField(int wireType) {
    switch (wireType) {
      case WireType.varint:
        readVarint();
      case WireType.fixed64:
        _position += 8;
      case WireType.lengthDelimited:
        final length = readVarint();
        _position += length;
      case WireType.startGroup:
        _skipGroup();
      case WireType.endGroup:
        break;
      case WireType.fixed32:
        _position += 4;
      default:
        throw StateError('Unknown wire type: $wireType');
    }

    if (_position > _data.length) {
      throw StateError('Skipped past end of data');
    }
  }

  void _skipGroup() {
    while (hasMore) {
      final tag = readTag();
      if (tag == null) break;

      final (_, wireType) = tag;
      if (wireType == WireType.endGroup) {
        break;
      }
      skipField(wireType);
    }
  }

  void reset() {
    _position = 0;
  }

  void seek(int position) {
    if (position < 0 || position > _data.length) {
      throw RangeError.range(position, 0, _data.length, 'position');
    }
    _position = position;
  }

  Uint8List readRemainingBytes() {
    final bytes = Uint8List.sublistView(_data, _position);
    _position = _data.length;
    return bytes;
  }

  ProtobufReader subReader(int length) {
    if (_position + length > _data.length) {
      throw StateError('Cannot create sub-reader past end of data');
    }

    final subData = Uint8List.sublistView(_data, _position, _position + length);
    _position += length;

    return ProtobufReader(subData);
  }
}

extension ProtobufReaderPackedExtension on ProtobufReader {
  List<int> readPackedVarints() {
    final bytes = readBytes();
    final reader = ProtobufReader(bytes);
    final result = <int>[];

    while (reader.hasMore) {
      result.add(reader.readVarint());
    }

    return result;
  }

  List<int> readPackedFixed32() {
    final bytes = readBytes();
    final count = bytes.length ~/ 4;
    final result = List<int>.filled(count, 0);
    final view = ByteData.sublistView(bytes);

    for (var i = 0; i < count; i++) {
      result[i] = view.getInt32(i * 4, Endian.little);
    }

    return result;
  }

  Float32List readPackedFloats() {
    final bytes = readBytes();
    final count = bytes.length ~/ 4;
    final result = Float32List(count);
    final view = ByteData.sublistView(bytes);

    for (var i = 0; i < count; i++) {
      result[i] = view.getFloat32(i * 4, Endian.little);
    }

    return result;
  }

  Float64List readPackedDoubles() {
    final bytes = readBytes();
    final count = bytes.length ~/ 8;
    final result = Float64List(count);
    final view = ByteData.sublistView(bytes);

    for (var i = 0; i < count; i++) {
      result[i] = view.getFloat64(i * 8, Endian.little);
    }

    return result;
  }
}
