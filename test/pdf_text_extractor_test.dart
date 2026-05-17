import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cotool/src/local_converter/pdf_text_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts text from compressed pdf content streams', () {
    final pdf = _pdfWithContentStream(
      'BT /F1 12 Tf 72 720 Td (Hello PDF) Tj T* (Second line) Tj ET',
      compressed: true,
    );

    final pages = const PdfTextExtractor().extractPages(pdf);

    expect(pages, hasLength(1));
    expect(pages.single, contains('Hello PDF'));
    expect(pages.single, contains('Second line'));
  });

  test('extracts text arrays and hex strings', () {
    final pdf = _pdfWithContentStream(
      'BT /F1 12 Tf 72 720 Td [(Hello ) 120 (array)] TJ T* <486578> Tj ET',
    );

    final pages = const PdfTextExtractor().extractPages(pdf);

    expect(pages.single, contains('Hello array'));
    expect(pages.single, contains('Hex'));
  });
}

Uint8List _pdfWithContentStream(String content, {bool compressed = false}) {
  final contentBytes = utf8.encode(content);
  final streamBytes = compressed
      ? const ZLibEncoder().encodeBytes(contentBytes)
      : contentBytes;
  final filter = compressed ? ' /Filter /FlateDecode' : '';

  final builder = BytesBuilder()
    ..add(ascii.encode('%PDF-1.4\n'))
    ..add(
      ascii.encode(
        '1 0 obj\n<< /Length ${streamBytes.length}$filter >>\nstream\n',
      ),
    )
    ..add(streamBytes)
    ..add(ascii.encode('\nendstream\nendobj\n%%EOF\n'));
  return builder.takeBytes();
}
