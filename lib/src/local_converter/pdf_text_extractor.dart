import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class PdfTextExtractor {
  const PdfTextExtractor();

  List<String> extractPages(Uint8List bytes) {
    final raw = latin1.decode(bytes, allowInvalid: true);
    final pages = <String>[];
    var searchStart = 0;

    while (searchStart < raw.length) {
      final streamStart = raw.indexOf('stream', searchStart);
      if (streamStart < 0) {
        break;
      }

      var dataStart = streamStart + 'stream'.length;
      if (raw.startsWith('\r\n', dataStart)) {
        dataStart += 2;
      } else if (dataStart < raw.length &&
          (raw.codeUnitAt(dataStart) == 10 ||
              raw.codeUnitAt(dataStart) == 13)) {
        dataStart++;
      }

      final streamEnd = raw.indexOf('endstream', dataStart);
      if (streamEnd < 0) {
        break;
      }

      var dataEnd = streamEnd;
      while (dataEnd > dataStart &&
          (bytes[dataEnd - 1] == 10 || bytes[dataEnd - 1] == 13)) {
        dataEnd--;
      }

      final objectStart = raw.lastIndexOf('obj', streamStart);
      final dictionaryStart = raw.lastIndexOf('<<', streamStart);
      final metadataStart = objectStart >= 0 ? objectStart : dictionaryStart;
      final metadata = metadataStart >= 0
          ? raw.substring(metadataStart, streamStart)
          : '';
      final streamBytes = bytes.sublist(dataStart, dataEnd);
      final decoded = _decodeStream(streamBytes, metadata);
      final text = _extractTextFromContentStream(decoded);
      if (text.trim().isNotEmpty) {
        pages.add(text.trimRight());
      }

      searchStart = streamEnd + 'endstream'.length;
    }

    return pages;
  }

  Uint8List _decodeStream(Uint8List bytes, String metadata) {
    if (!metadata.contains('/FlateDecode')) {
      return bytes;
    }

    try {
      return Uint8List.fromList(const ZLibDecoder().decodeBytes(bytes));
    } catch (_) {
      return bytes;
    }
  }

  String _extractTextFromContentStream(Uint8List bytes) {
    final source = latin1.decode(bytes, allowInvalid: true);
    final blocks = RegExp(r'BT(?<body>.*?)ET', dotAll: true).allMatches(source);
    final buffer = StringBuffer();

    for (final block in blocks) {
      final body = block.namedGroup('body') ?? '';
      _appendTextBlock(buffer, body);
    }

    return _normalizeExtractedText(buffer.toString());
  }

  void _appendTextBlock(StringBuffer buffer, String body) {
    final tokenPattern = RegExp(
      r'''(\[(?:\\.|[^\]])*?\]\s*TJ)|(\((?:\\.|[^\\)])*\)\s*(?:Tj|'|"))|(<[0-9A-Fa-f\s]+>\s*Tj)|(\bT\*|(?:-?\d+(?:\.\d+)?\s+){2}T[dD])''',
      dotAll: true,
    );

    for (final match in tokenPattern.allMatches(body)) {
      final token = match.group(0) ?? '';
      if (token == 'T*' || token.endsWith('Td') || token.endsWith('TD')) {
        _appendLineBreak(buffer);
      } else if (token.endsWith('TJ')) {
        _appendText(buffer, _decodeTextArray(token));
      } else if (token.contains('(')) {
        _appendText(buffer, _decodeLiteralString(token));
      } else if (token.startsWith('<')) {
        _appendText(buffer, _decodeHexString(token));
      }
    }
    _appendLineBreak(buffer);
  }

  String _decodeTextArray(String token) {
    final inside = token.substring(1, token.lastIndexOf(']'));
    final buffer = StringBuffer();
    final itemPattern = RegExp(
      r'\((?:\\.|[^\\)])*\)|<[0-9A-Fa-f\s]+>',
      dotAll: true,
    );
    for (final match in itemPattern.allMatches(inside)) {
      final value = match.group(0) ?? '';
      if (value.startsWith('(')) {
        buffer.write(_decodeLiteralString(value));
      } else {
        buffer.write(_decodeHexString(value));
      }
    }
    return buffer.toString();
  }

  String _decodeLiteralString(String token) {
    final start = token.indexOf('(');
    final end = token.lastIndexOf(')');
    if (start < 0 || end <= start) {
      return '';
    }

    final source = token.substring(start + 1, end);
    final bytes = <int>[];
    for (var index = 0; index < source.length; index++) {
      final codeUnit = source.codeUnitAt(index);
      if (codeUnit != 92) {
        bytes.add(codeUnit & 0xff);
        continue;
      }

      if (index + 1 >= source.length) {
        break;
      }
      final next = source.codeUnitAt(++index);
      switch (next) {
        case 110:
          bytes.add(10);
          break;
        case 114:
          bytes.add(13);
          break;
        case 116:
          bytes.add(9);
          break;
        case 98:
          bytes.add(8);
          break;
        case 102:
          bytes.add(12);
          break;
        case 40:
        case 41:
        case 92:
          bytes.add(next);
          break;
        case 10:
          break;
        case 13:
          if (index + 1 < source.length && source.codeUnitAt(index + 1) == 10) {
            index++;
          }
          break;
        default:
          if (_isOctalDigit(next)) {
            final octal = StringBuffer()..writeCharCode(next);
            var consumed = 0;
            while (consumed < 2 &&
                index + 1 < source.length &&
                _isOctalDigit(source.codeUnitAt(index + 1))) {
              octal.writeCharCode(source.codeUnitAt(++index));
              consumed++;
            }
            bytes.add(int.parse(octal.toString(), radix: 8) & 0xff);
          } else {
            bytes.add(next & 0xff);
          }
          break;
      }
    }

    return _decodePdfBytes(bytes);
  }

  String _decodeHexString(String token) {
    final start = token.indexOf('<');
    final end = token.indexOf('>', start + 1);
    if (start < 0 || end <= start) {
      return '';
    }

    var hex = token.substring(start + 1, end).replaceAll(RegExp(r'\s+'), '');
    if (hex.length.isOdd) {
      hex = '${hex}0';
    }

    final bytes = <int>[];
    for (var index = 0; index + 1 < hex.length; index += 2) {
      bytes.add(int.parse(hex.substring(index, index + 2), radix: 16));
    }
    return _decodePdfBytes(bytes);
  }

  String _decodePdfBytes(List<int> bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
      final codeUnits = <int>[];
      for (var index = 2; index + 1 < bytes.length; index += 2) {
        codeUnits.add((bytes[index] << 8) | bytes[index + 1]);
      }
      return String.fromCharCodes(codeUnits);
    }

    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  void _appendText(StringBuffer buffer, String text) {
    if (text.isEmpty) {
      return;
    }
    buffer.write(text);
  }

  void _appendLineBreak(StringBuffer buffer) {
    final text = buffer.toString();
    if (text.isEmpty || text.endsWith('\n')) {
      return;
    }
    buffer.writeln();
  }

  String _normalizeExtractedText(String value) {
    return value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trimRight();
  }

  bool _isOctalDigit(int codeUnit) {
    return codeUnit >= 48 && codeUnit <= 55;
  }
}
