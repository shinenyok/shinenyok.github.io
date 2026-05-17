import 'dart:async';

import '../platform/web_file_actions_stub.dart';

class LanTransferStatus {
  const LanTransferStatus({
    required this.isRunning,
    required this.lanUrls,
    required this.files,
    required this.messages,
  });

  const LanTransferStatus.offline()
    : isRunning = false,
      lanUrls = const [],
      files = const [],
      messages = const [];

  final bool isRunning;
  final List<String> lanUrls;
  final List<LanTransferFile> files;
  final List<LanTransferMessage> messages;
}

class LanTransferFile {
  const LanTransferFile({
    required this.id,
    required this.name,
    required this.size,
    required this.modifiedAt,
    required this.downloadUrl,
  });

  final String id;
  final String name;
  final int size;
  final DateTime modifiedAt;
  final String downloadUrl;
}

class LanTransferException implements Exception {
  const LanTransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LanTransferMessage {
  const LanTransferMessage({
    required this.id,
    required this.text,
    required this.sender,
    required this.createdAt,
  });

  final String id;
  final String text;
  final String sender;
  final DateTime createdAt;
}

Future<LanTransferStatus> probeLanTransfer() async {
  return const LanTransferStatus.offline();
}

Stream<LanTransferStatus> watchLanTransfer() {
  return const Stream<LanTransferStatus>.empty();
}

Future<LanTransferStatus> uploadLanTransferFile(PickedBinaryFile file) async {
  throw const LanTransferException('当前平台不能连接本地传输服务。');
}

Future<LanTransferStatus> deleteLanTransferFile(String id) async {
  throw const LanTransferException('当前平台不能连接本地传输服务。');
}

Future<LanTransferStatus> sendLanTransferMessage(String text) async {
  throw const LanTransferException('当前平台不能连接本地传输服务。');
}

Future<PickedBinaryFile> downloadLanTransferFile(LanTransferFile file) async {
  throw const LanTransferException('当前平台不能连接本地传输服务。');
}
