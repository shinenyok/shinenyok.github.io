import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;

import '../platform/web_file_actions_stub.dart'
    if (dart.library.html) '../platform/web_file_actions_web.dart';

class FileConverterService {
  Future<Uint8List> imagesToPdf(List<PickedBinaryFile> files) async {
    final document = pw.Document();
    for (final file in files) {
      for (final normalized in _normalizeImagePages(file)) {
        document.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (context) {
              return pw.Center(
                child: pw.Image(
                  pw.MemoryImage(normalized.bytes),
                  fit: pw.BoxFit.contain,
                ),
              );
            },
          ),
        );
      }
    }
    return document.save();
  }

  Future<Uint8List> imagesToDocx(List<PickedBinaryFile> files) async {
    final normalizedImages = [
      for (final file in files) ..._normalizeImagePages(file),
    ];
    final archive = Archive()
      ..addFile(_textFile('[Content_Types].xml', _contentTypesXml))
      ..addFile(_textFile('_rels/.rels', _rootRelationshipsXml))
      ..addFile(
        _textFile(
          'word/_rels/document.xml.rels',
          _documentRelationshipsXml(normalizedImages.length),
        ),
      )
      ..addFile(_textFile('word/document.xml', _documentXml(normalizedImages)));

    for (var index = 0; index < normalizedImages.length; index++) {
      final image = normalizedImages[index];
      archive.addFile(
        ArchiveFile(
          'word/media/image${index + 1}.png',
          image.bytes.length,
          image.bytes,
        ),
      );
    }

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<Uint8List> pdfToImageZip(PickedBinaryFile file) async {
    final archive = Archive();
    var pageNumber = 1;
    await for (final page in Printing.raster(file.bytes, dpi: 144)) {
      final png = await page.toPng();
      final name = 'page_${pageNumber.toString().padLeft(2, '0')}.png';
      archive.addFile(ArchiveFile(name, png.length, png));
      pageNumber++;
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<Uint8List> pdfToEditableDocx(PickedBinaryFile file) async {
    sfpdf.PdfDocument? document;
    try {
      document = sfpdf.PdfDocument(inputBytes: file.bytes);
      final extractor = sfpdf.PdfTextExtractor(document);
      final pages = <String>[];

      for (var index = 0; index < document.pages.count; index++) {
        final text = _extractPageText(extractor, index);
        if (text.trim().isNotEmpty) {
          pages.add(text.trimRight());
        }
      }

      if (pages.isEmpty) {
        throw const FormatException('没有提取到可编辑文字。这个 PDF 可能是扫描件，或需要 OCR。');
      }

      return _textPagesToDocx(pages);
    } finally {
      document?.dispose();
    }
  }

  List<_NormalizedImage> _normalizeImagePages(PickedBinaryFile file) {
    final decoded = img.decodeImage(file.bytes);
    if (decoded == null) {
      throw FormatException('${file.name} 不是可解析的图片。');
    }

    final maxSliceHeight = _maxImageSliceHeight(decoded.width);
    if (decoded.height <= maxSliceHeight) {
      return [_normalizeDecodedImage(name: file.name, image: decoded)];
    }

    final pages = <_NormalizedImage>[];
    var y = 0;
    var pageNumber = 1;
    while (y < decoded.height) {
      final sliceHeight = math.min(maxSliceHeight, decoded.height - y);
      final slice = img.copyCrop(
        decoded,
        x: 0,
        y: y,
        width: decoded.width,
        height: sliceHeight,
      );
      pages.add(
        _normalizeDecodedImage(
          name: _imagePartName(file.name, pageNumber),
          image: slice,
        ),
      );
      y += sliceHeight;
      pageNumber++;
    }
    return pages;
  }

  _NormalizedImage _normalizeDecodedImage({
    required String name,
    required img.Image image,
  }) {
    final pngBytes = Uint8List.fromList(img.encodePng(image));
    return _NormalizedImage(
      name: name,
      bytes: pngBytes,
      width: image.width,
      height: image.height,
    );
  }

  int _maxImageSliceHeight(int width) {
    final height = (width * _wordContentHeightTwips / _wordContentWidthTwips)
        .floor();
    return math.max(1, height);
  }

  String _imagePartName(String name, int partNumber) {
    final dotIndex = name.lastIndexOf('.');
    final baseName = dotIndex > 0 ? name.substring(0, dotIndex) : name;
    final paddedPart = partNumber.toString().padLeft(2, '0');
    return '$baseName-page-$paddedPart.png';
  }

  Uint8List _textPagesToDocx(List<String> pages) {
    final archive = Archive()
      ..addFile(_textFile('[Content_Types].xml', _contentTypesXml))
      ..addFile(_textFile('_rels/.rels', _rootRelationshipsXml))
      ..addFile(_textFile('word/document.xml', _textDocumentXml(pages)));

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  String _extractPageText(sfpdf.PdfTextExtractor extractor, int pageIndex) {
    final lines = extractor.extractTextLines(
      startPageIndex: pageIndex,
      endPageIndex: pageIndex,
    );
    if (lines.isEmpty) {
      return extractor.extractText(
        startPageIndex: pageIndex,
        endPageIndex: pageIndex,
        layoutText: true,
      );
    }

    return lines.map(_textLineText).where((line) => line.isNotEmpty).join('\n');
  }

  String _textLineText(sfpdf.TextLine line) {
    final words = line.wordCollection
        .map((word) => word.text.trim())
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.length > 1) {
      return words.join(' ');
    }

    return line.text.trimRight();
  }
}

class _NormalizedImage {
  const _NormalizedImage({
    required this.name,
    required this.bytes,
    required this.width,
    required this.height,
  });

  final String name;
  final Uint8List bytes;
  final int width;
  final int height;
}

ArchiveFile _textFile(String path, String content) {
  final bytes = Uint8List.fromList(utf8.encode(content));
  return ArchiveFile(path, bytes.length, bytes);
}

String _documentRelationshipsXml(int imageCount) {
  final imageRelationships = Iterable.generate(imageCount, (index) {
    final id = index + 1;
    return '<Relationship Id="rId$id" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
        'Target="media/image$id.png"/>';
  }).join();

  return '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  $imageRelationships
</Relationships>
''';
}

String _documentXml(List<_NormalizedImage> images) {
  final body = images.asMap().entries.map((entry) {
    final index = entry.key;
    final image = entry.value;
    return _imageParagraph(
      relationshipId: 'rId${index + 1}',
      name: _escapeXml(image.name),
      width: image.width,
      height: image.height,
      pageBreakBefore: index > 0,
    );
  }).join();

  return '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
  xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
  xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
  <w:body>
    $body
    <w:sectPr>
      <w:pgSz w:w="$_wordPageWidthTwips" w:h="$_wordPageHeightTwips"/>
      <w:pgMar w:top="$_wordPageMarginTwips" w:right="$_wordPageMarginTwips" w:bottom="$_wordPageMarginTwips" w:left="$_wordPageMarginTwips" w:header="360" w:footer="360" w:gutter="0"/>
    </w:sectPr>
  </w:body>
</w:document>
''';
}

String _imageParagraph({
  required String relationshipId,
  required String name,
  required int width,
  required int height,
  required bool pageBreakBefore,
}) {
  final originalWidth = width * _emuPerPixel;
  final originalHeight = height * _emuPerPixel;
  final widthScale = _maxImageWidthEmu / originalWidth;
  final heightScale = _maxImageHeightEmu / originalHeight;
  final scale = math.min(1.0, math.min(widthScale, heightScale));
  final cx = (originalWidth * scale).round();
  final cy = (originalHeight * scale).round();
  final pageBreak = pageBreakBefore ? '<w:pageBreakBefore/>' : '';

  return '''
    <w:p>
      <w:pPr>
        $pageBreak
        <w:jc w:val="center"/>
        <w:spacing w:before="0" w:after="0"/>
      </w:pPr>
      <w:r>
        <w:drawing>
          <wp:inline distT="0" distB="0" distL="0" distR="0">
            <wp:extent cx="$cx" cy="$cy"/>
            <wp:docPr id="${relationshipId.substring(3)}" name="$name"/>
            <a:graphic>
              <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                <pic:pic>
                  <pic:nvPicPr>
                    <pic:cNvPr id="0" name="$name"/>
                    <pic:cNvPicPr/>
                  </pic:nvPicPr>
                  <pic:blipFill>
                    <a:blip r:embed="$relationshipId"/>
                    <a:stretch><a:fillRect/></a:stretch>
                  </pic:blipFill>
                  <pic:spPr>
                    <a:xfrm>
                      <a:off x="0" y="0"/>
                      <a:ext cx="$cx" cy="$cy"/>
                    </a:xfrm>
                    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                  </pic:spPr>
                </pic:pic>
              </a:graphicData>
            </a:graphic>
          </wp:inline>
        </w:drawing>
      </w:r>
    </w:p>
''';
}

String _textDocumentXml(List<String> pages) {
  final paragraphs = <String>[];
  for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
    final lines = pages[pageIndex]
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList();

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      paragraphs.add(
        _textParagraph(
          lines[lineIndex],
          pageBreakBefore: pageIndex > 0 && lineIndex == 0,
        ),
      );
    }
  }

  return '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    ${paragraphs.join()}
    <w:sectPr>
      <w:pgSz w:w="$_wordPageWidthTwips" w:h="$_wordPageHeightTwips"/>
      <w:pgMar w:top="$_wordPageMarginTwips" w:right="$_wordPageMarginTwips" w:bottom="$_wordPageMarginTwips" w:left="$_wordPageMarginTwips" w:header="360" w:footer="360" w:gutter="0"/>
    </w:sectPr>
  </w:body>
</w:document>
''';
}

String _textParagraph(String text, {required bool pageBreakBefore}) {
  final pageBreak = pageBreakBefore ? '<w:pageBreakBefore/>' : '';
  final escapedText = _escapeXml(text);

  return '''
    <w:p>
      <w:pPr>
        $pageBreak
        <w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/>
      </w:pPr>
      <w:r>
        <w:rPr>
          <w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:eastAsia="DengXian"/>
          <w:sz w:val="20"/>
        </w:rPr>
        <w:t xml:space="preserve">$escapedText</w:t>
      </w:r>
    </w:p>
''';
}

const int _wordPageWidthTwips = 11906;
const int _wordPageHeightTwips = 16838;
const int _wordPageMarginTwips = 720;
const int _wordContentWidthTwips =
    _wordPageWidthTwips - (_wordPageMarginTwips * 2);
const int _wordContentHeightTwips =
    _wordPageHeightTwips - (_wordPageMarginTwips * 2);
const int _emuPerTwip = 635;
const int _maxImageWidthEmu = _wordContentWidthTwips * _emuPerTwip;
const int _maxImageHeightEmu = _wordContentHeightTwips * _emuPerTwip;
const int _emuPerPixel = 9525;

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

const String _contentTypesXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="png" ContentType="image/png"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
''';

const String _rootRelationshipsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
''';
