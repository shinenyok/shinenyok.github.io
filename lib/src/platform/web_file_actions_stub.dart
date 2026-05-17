import 'dart:typed_data';

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

Future<PickedImageFile?> pickImageFile() async => null;

Future<List<PickedBinaryFile>> pickBinaryFiles({
  required String accept,
  bool multiple = false,
}) async {
  return const [];
}

Future<bool> saveBinaryFile({
  required Uint8List bytes,
  required String filename,
  required String fileExtension,
  required String mimeType,
}) async {
  return false;
}

Future<bool> saveZip(Uint8List bytes, String filename) async => false;
