// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import '../platform/web_file_actions_web.dart';
import 'lan_transfer_client_stub.dart';

export 'lan_transfer_client_stub.dart'
    show
        LanTransferException,
        LanTransferFile,
        LanTransferMessage,
        LanTransferStatus;

const _localTransferPort = 8787;
const _loopbackBaseUrl = 'http://127.0.0.1:$_localTransferPort';
String _activeBaseUrl = _loopbackBaseUrl;

Future<LanTransferStatus> probeLanTransfer() async {
  for (final baseUrl in _candidateBaseUrls()) {
    try {
      final request = await html.HttpRequest.request(
        '$baseUrl/transfer/status',
        method: 'GET',
        responseType: 'text',
      ).timeout(const Duration(milliseconds: 1200));
      if (request.status != 200) {
        continue;
      }
      _activeBaseUrl = baseUrl;
      return _statusFromJson(jsonDecode(request.responseText ?? '{}'), baseUrl);
    } catch (_) {
      // Try the next local address candidate.
    }
  }

  return const LanTransferStatus.offline();
}

Stream<LanTransferStatus> watchLanTransfer() {
  late final StreamController<LanTransferStatus> controller;
  late final Future<void> Function() connect;
  html.WebSocket? socket;
  Timer? reconnectTimer;
  var disposed = false;
  var connecting = false;

  void scheduleReconnect() {
    if (disposed) {
      return;
    }
    reconnectTimer?.cancel();
    reconnectTimer = Timer(const Duration(seconds: 2), () {
      unawaited(connect());
    });
  }

  connect = () async {
    if (disposed || connecting) {
      return;
    }
    connecting = true;

    for (final baseUrl in _candidateBaseUrls()) {
      if (disposed) {
        break;
      }

      html.WebSocket? candidate;
      try {
        candidate = html.WebSocket(_webSocketUrl(baseUrl));
        await candidate.onOpen.first.timeout(
          const Duration(milliseconds: 1400),
        );
        if (disposed) {
          candidate.close();
          return;
        }

        socket = candidate;
        _activeBaseUrl = baseUrl;
        candidate.onMessage.listen((event) {
          final status = _statusFromSocketMessage(event.data, baseUrl);
          if (status != null && !controller.isClosed) {
            controller.add(status);
          }
        });

        void disconnect() {
          if (socket == candidate) {
            socket = null;
          }
          scheduleReconnect();
        }

        candidate.onClose.first.then((_) => disconnect());
        candidate.onError.first.then((_) => disconnect());
        candidate.send(jsonEncode({'type': 'refresh'}));
        connecting = false;
        return;
      } catch (_) {
        try {
          candidate?.close();
        } catch (_) {
          // Ignore close failures while probing WebSocket candidates.
        }
      }
    }

    connecting = false;
    scheduleReconnect();
  };

  controller = StreamController<LanTransferStatus>(
    onListen: () => unawaited(connect()),
    onCancel: () {
      disposed = true;
      reconnectTimer?.cancel();
      socket?.close();
      socket = null;
    },
  );
  return controller.stream;
}

Future<LanTransferStatus> uploadLanTransferFile(PickedBinaryFile file) async {
  final form = html.FormData()
    ..appendBlob('file', html.Blob([file.bytes], file.mimeType), file.name);
  final request = await _request(
    '/transfer/upload',
    method: 'POST',
    sendData: form,
  );
  if (request.status != 200) {
    throw LanTransferException(_readErrorMessage(request.responseText));
  }
  return probeLanTransfer();
}

Future<LanTransferStatus> deleteLanTransferFile(String id) async {
  final request = await _request(
    '/transfer/files/${Uri.encodeComponent(id)}',
    method: 'DELETE',
  );
  if (request.status != 200) {
    throw LanTransferException(_readErrorMessage(request.responseText));
  }
  return probeLanTransfer();
}

Future<LanTransferStatus> sendLanTransferMessage(String text) async {
  try {
    await _sendSocketCommand({'type': 'message', 'text': text});
    return probeLanTransfer();
  } catch (_) {
    // Older local services may not expose WebSocket yet; keep HTTP as fallback.
  }

  final request = await _request(
    '/transfer/messages',
    method: 'POST',
    sendData: jsonEncode({'text': text}),
    headers: {'Content-Type': 'application/json'},
  );
  if (request.status != 200) {
    throw LanTransferException(_readErrorMessage(request.responseText));
  }
  return probeLanTransfer();
}

Future<void> _sendSocketCommand(Map<String, Object?> command) async {
  var timedOut = false;
  for (final baseUrl in _candidateBaseUrls()) {
    html.WebSocket? socket;
    try {
      socket = html.WebSocket(_webSocketUrl(baseUrl));
      await socket.onOpen.first.timeout(const Duration(milliseconds: 1400));
      _activeBaseUrl = baseUrl;
      socket.send(jsonEncode(command));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      socket.close();
      return;
    } on TimeoutException {
      timedOut = true;
      socket?.close();
    } catch (_) {
      socket?.close();
    }
  }

  if (timedOut) {
    throw TimeoutException('local transfer websocket timed out');
  }
  throw const LanTransferException('无法连接本地传输服务。');
}

Future<PickedBinaryFile> downloadLanTransferFile(LanTransferFile file) async {
  late html.HttpRequest request;
  try {
    request = await _sendHttpRequest(
      file.downloadUrl,
      method: 'GET',
      responseType: 'arraybuffer',
      timeout: const Duration(minutes: 2),
    );
  } on TimeoutException {
    throw const LanTransferException('文件下载超时。');
  } catch (_) {
    throw const LanTransferException('无法下载文件。');
  }

  final bytes = _responseBytes(request.response);
  if (request.status != 200 || bytes.isEmpty) {
    throw const LanTransferException('文件下载失败。');
  }

  return PickedBinaryFile(
    name: file.name,
    mimeType:
        request.getResponseHeader('Content-Type') ?? 'application/octet-stream',
    bytes: bytes,
  );
}

Future<html.HttpRequest> _request(
  String path, {
  required String method,
  Object? sendData,
  Map<String, String>? headers,
}) async {
  var timedOut = false;
  for (final baseUrl in _candidateBaseUrls()) {
    try {
      final request = await _sendHttpRequest(
        '$baseUrl$path',
        method: method,
        sendData: sendData,
        responseType: 'text',
        headers: headers,
        timeout: const Duration(minutes: 2),
      );
      _activeBaseUrl = baseUrl;
      return request;
    } on TimeoutException {
      timedOut = true;
    } catch (_) {
      // Try the next local address candidate.
    }
  }

  if (timedOut) {
    throw const LanTransferException('本地传输服务响应超时。');
  }
  throw const LanTransferException('无法连接本地传输服务。');
}

Future<html.HttpRequest> _sendHttpRequest(
  String url, {
  required String method,
  Object? sendData,
  required String responseType,
  Map<String, String>? headers,
  required Duration timeout,
}) {
  final completer = Completer<html.HttpRequest>();
  final request = html.HttpRequest()
    ..open(method, url)
    ..responseType = responseType
    ..timeout = timeout.inMilliseconds;
  headers?.forEach(request.setRequestHeader);

  void completeError(Object error) {
    if (!completer.isCompleted) {
      completer.completeError(error);
    }
  }

  request.onLoad.first.then((_) {
    if (!completer.isCompleted) {
      completer.complete(request);
    }
  });
  request.onError.first.then((_) {
    completeError(const _NetworkRequestException());
  });
  request.onTimeout.first.then((_) {
    completeError(TimeoutException('local transfer timed out'));
  });

  try {
    request.send(sendData);
  } catch (error) {
    completeError(error);
  }
  return completer.future;
}

Uint8List _responseBytes(Object? response) {
  if (response is ByteBuffer) {
    return Uint8List.view(response);
  }
  if (response is Uint8List) {
    return response;
  }
  return Uint8List(0);
}

LanTransferStatus _statusFromJson(Object? payload, String baseUrl) {
  if (payload is! Map<String, dynamic>) {
    return const LanTransferStatus.offline();
  }
  final urls = payload['lanUrls'];
  final files = payload['files'];
  final messages = payload['messages'];
  return LanTransferStatus(
    isRunning: payload['ok'] == true,
    lanUrls: urls is List ? urls.map((url) => '$url/share').toList() : const [],
    files: files is List
        ? files
              .whereType<Map<String, dynamic>>()
              .map((json) => _fileFromJson(json, baseUrl))
              .toList(growable: false)
        : const [],
    messages: messages is List
        ? messages
              .whereType<Map<String, dynamic>>()
              .map(_messageFromJson)
              .toList(growable: false)
        : const [],
  );
}

LanTransferFile _fileFromJson(Map<String, dynamic> json, String baseUrl) {
  final modifiedAt = DateTime.tryParse(json['modifiedAt']?.toString() ?? '');
  return LanTransferFile(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'file',
    size: json['size'] is int ? json['size'] as int : 0,
    modifiedAt: modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    downloadUrl: '$baseUrl${json['downloadUrl'] ?? ''}',
  );
}

List<String> _candidateBaseUrls() {
  final urls = <String>[
    _activeBaseUrl,
    _loopbackBaseUrl,
    'http://localhost:$_localTransferPort',
  ];
  final currentHost = html.window.location.hostname ?? '';
  if (currentHost.isNotEmpty && currentHost != '0.0.0.0') {
    urls.add('http://$currentHost:$_localTransferPort');
  }
  return urls.toSet().toList(growable: false);
}

String _webSocketUrl(String baseUrl) {
  final uri = Uri.parse(baseUrl);
  final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
  return uri.replace(scheme: scheme, path: '/transfer/ws').toString();
}

LanTransferStatus? _statusFromSocketMessage(Object? data, String baseUrl) {
  if (data is! String) {
    return null;
  }

  try {
    final payload = jsonDecode(data);
    if (payload is Map<String, dynamic> && payload['type'] == 'status') {
      return _statusFromJson(payload['payload'], baseUrl);
    }
  } catch (_) {
    // Ignore malformed socket frames.
  }
  return null;
}

LanTransferMessage _messageFromJson(Map<String, dynamic> json) {
  final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
  return LanTransferMessage(
    id: json['id']?.toString() ?? '',
    text: json['text']?.toString() ?? '',
    sender: json['sender']?.toString() ?? 'unknown',
    createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}

String _readErrorMessage(String? text) {
  try {
    final payload = jsonDecode(text ?? '{}');
    if (payload is Map<String, dynamic>) {
      final error = payload['error'];
      if (error is String && error.trim().isNotEmpty) {
        return error;
      }
    }
  } catch (_) {
    // Fall through to the generic message.
  }
  return '局域网传输失败。';
}

class _NetworkRequestException implements Exception {
  const _NetworkRequestException();
}
