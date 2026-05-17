// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import '../platform/web_file_actions_web.dart';
import 'local_converter_client_stub.dart';

export 'local_converter_client_stub.dart'
    show LocalConversionResult, LocalConverterException, LocalConverterStatus;

const _localConverterPort = 8787;
const _loopbackBaseUrl = 'http://127.0.0.1:$_localConverterPort';
String _activeBaseUrl = _loopbackBaseUrl;

Future<LocalConverterStatus> probeLocalConverter() async {
  for (final baseUrl in _candidateBaseUrls()) {
    try {
      final request = await html.HttpRequest.request(
        '$baseUrl/health',
        method: 'GET',
        responseType: 'text',
      ).timeout(const Duration(milliseconds: 1200));

      if (request.status != 200) {
        continue;
      }

      final payload = jsonDecode(request.responseText ?? '{}');
      if (payload is! Map<String, dynamic>) {
        continue;
      }

      _activeBaseUrl = baseUrl;
      final features = payload['features'];
      final missing = payload['missing'];
      return LocalConverterStatus(
        isRunning: true,
        pdfToEditableWord: _readBool(features, 'pdfToEditableWord'),
        wordToPdf: _readBool(features, 'wordToPdf'),
        wordToImages: _readBool(features, 'wordToImages'),
        missingTools: missing is List
            ? missing.map((item) => item.toString()).toList()
            : const [],
      );
    } catch (_) {
      // Try the next local address candidate.
    }
  }

  return const LocalConverterStatus.offline();
}

Future<LocalConversionResult> convertPdfToEditableWord(
  PickedBinaryFile file,
) async {
  return _postFile('/convert/pdf-to-word', file, fallbackExtension: 'docx');
}

Future<LocalConversionResult> convertWordToPdf(PickedBinaryFile file) async {
  return _postFile('/convert/word-to-pdf', file, fallbackExtension: 'pdf');
}

Future<LocalConversionResult> _postFile(
  String path,
  PickedBinaryFile file, {
  required String fallbackExtension,
}) async {
  final form = html.FormData()
    ..appendBlob('file', html.Blob([file.bytes], file.mimeType), file.name);

  late html.HttpRequest request;
  try {
    request = await _postForm(path, form);
  } on TimeoutException {
    throw const LocalConverterException('本地转换服务响应超时。');
  } on LocalConverterException {
    rethrow;
  } catch (_) {
    throw const LocalConverterException('无法连接本地转换服务。');
  }

  final bytes = _responseBytes(request.response);
  if (request.status != 200) {
    throw LocalConverterException(_readErrorMessage(bytes));
  }

  final filename =
      _filenameFromDisposition(
        request.getResponseHeader('Content-Disposition'),
      ) ??
      _fallbackFilename(file.name, fallbackExtension);
  return LocalConversionResult(
    bytes: bytes,
    filename: filename,
    mimeType:
        request.getResponseHeader('Content-Type') ?? 'application/octet-stream',
  );
}

Future<html.HttpRequest> _postForm(String path, html.FormData form) async {
  var timedOut = false;
  for (final baseUrl in _candidateBaseUrls()) {
    try {
      final request = await _sendHttpRequest(
        '$baseUrl$path',
        method: 'POST',
        sendData: form,
        responseType: 'arraybuffer',
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
    throw TimeoutException('local converter timed out');
  }
  throw const LocalConverterException('无法连接本地转换服务。');
}

Future<html.HttpRequest> _sendHttpRequest(
  String url, {
  required String method,
  Object? sendData,
  required String responseType,
  required Duration timeout,
}) {
  final completer = Completer<html.HttpRequest>();
  final request = html.HttpRequest()
    ..open(method, url)
    ..responseType = responseType
    ..timeout = timeout.inMilliseconds;

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
    completeError(TimeoutException('local converter timed out'));
  });

  try {
    request.send(sendData);
  } catch (error) {
    completeError(error);
  }
  return completer.future;
}

List<String> _candidateBaseUrls() {
  final urls = <String>[
    _activeBaseUrl,
    _loopbackBaseUrl,
    'http://localhost:$_localConverterPort',
  ];
  final currentHost = html.window.location.hostname ?? '';
  if (currentHost.isNotEmpty && currentHost != '0.0.0.0') {
    urls.add('http://$currentHost:$_localConverterPort');
  }
  return urls.toSet().toList(growable: false);
}

bool _readBool(Object? source, String key) {
  return source is Map<String, dynamic> && source[key] == true;
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

String _readErrorMessage(Uint8List bytes) {
  try {
    final payload = jsonDecode(utf8.decode(bytes));
    if (payload is Map<String, dynamic>) {
      final error = payload['error'];
      if (error is String && error.trim().isNotEmpty) {
        return error;
      }
    }
  } catch (_) {
    // Fall through to the generic message.
  }
  return '本地转换失败。';
}

String? _filenameFromDisposition(String? disposition) {
  if (disposition == null) {
    return null;
  }
  final match = RegExp(r'filename="([^"]+)"').firstMatch(disposition);
  return match?.group(1);
}

String _fallbackFilename(String originalName, String extension) {
  final dotIndex = originalName.lastIndexOf('.');
  final baseName = dotIndex > 0
      ? originalName.substring(0, dotIndex)
      : originalName;
  return '$baseName.$extension';
}

class _NetworkRequestException implements Exception {
  const _NetworkRequestException();
}
