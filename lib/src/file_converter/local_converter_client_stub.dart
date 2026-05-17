import 'dart:typed_data';

import '../platform/web_file_actions_stub.dart';

class LocalConverterStatus {
  const LocalConverterStatus({
    required this.isRunning,
    required this.pdfToEditableWord,
    required this.wordToPdf,
    required this.wordToImages,
    required this.missingTools,
  });

  const LocalConverterStatus.offline()
    : isRunning = false,
      pdfToEditableWord = false,
      wordToPdf = false,
      wordToImages = false,
      missingTools = const [];

  final bool isRunning;
  final bool pdfToEditableWord;
  final bool wordToPdf;
  final bool wordToImages;
  final List<String> missingTools;
}

class LocalConversionResult {
  const LocalConversionResult({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
}

class LocalConverterException implements Exception {
  const LocalConverterException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<LocalConverterStatus> probeLocalConverter() async {
  return const LocalConverterStatus.offline();
}

Future<LocalConversionResult> convertPdfToEditableWord(
  PickedBinaryFile file,
) async {
  throw const LocalConverterException('当前平台不能连接本地转换服务。');
}

Future<LocalConversionResult> convertWordToPdf(PickedBinaryFile file) async {
  throw const LocalConverterException('当前平台不能连接本地转换服务。');
}
