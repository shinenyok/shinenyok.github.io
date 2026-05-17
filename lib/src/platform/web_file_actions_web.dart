// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

class PickedImageFile {
  const PickedImageFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class PickedBinaryFile {
  const PickedBinaryFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

Future<PickedImageFile?> pickImageFile() async {
  final files = await pickBinaryFiles(
    accept: 'image/png,image/jpeg,image/webp',
  );
  final file = files.firstOrNull;
  if (file == null) {
    return null;
  }
  return PickedImageFile(name: file.name, bytes: file.bytes);
}

Future<List<PickedBinaryFile>> pickBinaryFiles({
  required String accept,
  bool multiple = false,
}) async {
  final input = html.FileUploadInputElement()
    ..accept = accept
    ..multiple = multiple
    ..style.position = 'fixed'
    ..style.left = '-1000px'
    ..style.top = '-1000px'
    ..style.opacity = '0';

  html.document.body?.append(input);
  input.click();

  try {
    await input.onChange.first;
    final files = input.files;
    if (files == null || files.isEmpty) {
      return const [];
    }

    final pickedFiles = <PickedBinaryFile>[];
    for (final file in files) {
      final bytes = await _readFileBytes(file);
      pickedFiles.add(
        PickedBinaryFile(name: file.name, mimeType: file.type, bytes: bytes),
      );
    }
    return pickedFiles;
  } finally {
    input.remove();
  }
}

Future<Uint8List> _readFileBytes(html.File file) async {
  final reader = html.FileReader();
  reader.readAsArrayBuffer(file);
  await Future.any([
    reader.onLoad.first,
    reader.onError.first.then((_) {
      throw StateError('Unable to read selected file.');
    }),
  ]);

  final result = reader.result;
  if (result is ByteBuffer) {
    return Uint8List.view(result);
  }
  if (result is Uint8List) {
    return result;
  }

  throw StateError('Unsupported file reader result: ${result.runtimeType}');
}

Future<bool> saveBinaryFile({
  required Uint8List bytes,
  required String filename,
  required String fileExtension,
  required String mimeType,
}) async {
  final suffix = '.$fileExtension';
  final name = filename.endsWith(suffix)
      ? filename.substring(0, filename.length - suffix.length)
      : filename;

  await FileSaver.instance.saveAs(
    name: name,
    bytes: bytes,
    fileExtension: fileExtension,
    mimeType: MimeType.custom,
    customMimeType: mimeType,
  );
  return true;
}

Future<bool> saveZip(Uint8List bytes, String filename) async {
  return saveBinaryFile(
    bytes: bytes,
    filename: filename,
    fileExtension: 'zip',
    mimeType: 'application/zip',
  );
}
