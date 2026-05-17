import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:cotool/src/file_converter/file_converter_service.dart';
import 'package:cotool/src/platform/web_file_actions_stub.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

void main() {
  test('converts images to pdf and docx bytes', () async {
    final image = img.Image(width: 8, height: 8)
      ..clear(img.ColorRgb8(31, 138, 112));
    final file = PickedBinaryFile(
      name: 'sample.png',
      mimeType: 'image/png',
      bytes: img.encodePng(image),
    );
    final service = FileConverterService();

    final pdf = await service.imagesToPdf([file]);
    final docx = await service.imagesToDocx([file]);
    final docxArchive = ZipDecoder().decodeBytes(docx);

    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    expect(
      docxArchive.files.map((file) => file.name),
      containsAll([
        '[Content_Types].xml',
        'word/document.xml',
        'word/media/image1.png',
      ]),
    );
  });

  test('splits tall images across docx pages', () async {
    final image = img.Image(width: 100, height: 500)
      ..clear(img.ColorRgb8(31, 138, 112));
    final file = PickedBinaryFile(
      name: 'tall.png',
      mimeType: 'image/png',
      bytes: img.encodePng(image),
    );
    final service = FileConverterService();

    final docx = await service.imagesToDocx([file]);
    final docxArchive = ZipDecoder().decodeBytes(docx);
    final mediaFiles = docxArchive.files.where(
      (file) => file.name.startsWith('word/media/image'),
    );
    final documentXml = utf8.decode(
      docxArchive.files
          .singleWhere((file) => file.name == 'word/document.xml')
          .content,
    );

    expect(mediaFiles.length, greaterThan(1));
    expect(documentXml, contains('w:pageBreakBefore'));
  });

  test('converts selectable pdf text to editable docx bytes', () async {
    final document = pw.Document()
      ..addPage(pw.Page(build: (context) => pw.Text('Hello editable PDF')));
    final service = FileConverterService();
    final file = PickedBinaryFile(
      name: 'text.pdf',
      mimeType: 'application/pdf',
      bytes: await document.save(),
    );

    final docx = await service.pdfToEditableDocx(file);
    final docxArchive = ZipDecoder().decodeBytes(docx);
    final documentXml = utf8.decode(
      docxArchive.files
          .singleWhere((file) => file.name == 'word/document.xml')
          .content,
    );

    expect(documentXml, contains('Hello editable PDF'));
  });
}
