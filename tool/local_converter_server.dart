import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cotool/src/local_converter/pdf_text_extractor.dart';
import 'package:qr/qr.dart';

const _defaultPort = 8787;
const _docxMimeType =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
late final Directory _transferDirectory;
late final int _serverPort;
final List<_TransferMessage> _transferMessages = [];
final Set<WebSocket> _transferSockets = {};

Future<void> main(List<String> arguments) async {
  _serverPort = _readPort(arguments);
  _transferDirectory = Directory('${Directory.current.path}/.cotool_transfer');
  await _transferDirectory.create(recursive: true);
  final servers = await _bindServers(_serverPort);

  stdout.writeln('cotool local converter is running:');
  stdout.writeln('  http://127.0.0.1:$_serverPort');
  stdout.writeln('LAN transfer page:');
  for (final url in await _localAccessUrls(_serverPort)) {
    stdout.writeln('  $url/share');
  }
  stdout.writeln('Press Ctrl+C to stop.');

  await Future.wait(servers.map(_serveRequests));
}

Future<List<HttpServer>> _bindServers(int port) async {
  final servers = <HttpServer>[];
  final errors = <String>[];

  for (final address in [
    InternetAddress.loopbackIPv4,
    InternetAddress.anyIPv4,
  ]) {
    try {
      servers.add(await HttpServer.bind(address, port, shared: true));
    } on SocketException catch (error) {
      errors.add('${address.address}:$port (${error.message})');
    }
  }

  if (servers.isEmpty) {
    throw StateError('无法启动本地转换服务，端口 $port 不可用：${errors.join('; ')}');
  }

  if (errors.isNotEmpty) {
    stderr.writeln('部分地址监听失败：${errors.join('; ')}');
  }
  return servers;
}

Future<void> _serveRequests(HttpServer server) async {
  await for (final request in server) {
    unawaited(_handleRequest(request));
  }
}

int _readPort(List<String> arguments) {
  for (var index = 0; index < arguments.length; index++) {
    if (arguments[index] == '--port' && index + 1 < arguments.length) {
      return int.tryParse(arguments[index + 1]) ?? _defaultPort;
    }
  }
  return _defaultPort;
}

Future<void> _handleRequest(HttpRequest request) async {
  _setCorsHeaders(request.response);

  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
    return;
  }

  try {
    final path = request.uri.path;
    if (request.method == 'GET' &&
        path == '/transfer/ws' &&
        WebSocketTransformer.isUpgradeRequest(request)) {
      await _handleTransferSocket(request);
      return;
    }

    if (request.method == 'GET' && path == '/health') {
      await _sendJson(request.response, await _healthPayload());
      return;
    }

    if (request.method == 'GET' && (path == '/' || path == '/share')) {
      await _sendHtml(request.response, _sharePageHtml(request));
      return;
    }

    if (request.method == 'GET' && path == '/transfer/status') {
      await _sendJson(request.response, await _transferStatusPayload());
      return;
    }

    if (request.method == 'GET' && path == '/transfer/files') {
      await _sendJson(request.response, {'files': await _transferFiles()});
      return;
    }

    if (request.method == 'GET' && path == '/transfer/messages') {
      await _sendJson(request.response, {
        'messages': _transferMessagePayloads(),
      });
      return;
    }

    if (request.method == 'POST' && path == '/transfer/messages') {
      await _handleTransferMessage(request);
      return;
    }

    if (request.method == 'POST' && path == '/transfer/upload') {
      await _handleTransferUpload(request);
      return;
    }

    if (request.method == 'GET' && path.startsWith('/transfer/download/')) {
      await _handleTransferDownload(request);
      return;
    }

    if (request.method == 'DELETE' && path.startsWith('/transfer/files/')) {
      await _handleTransferDelete(request);
      return;
    }

    if (request.method == 'POST' && path == '/convert/pdf-to-word') {
      await _handlePdfToWord(request);
      return;
    }

    if (request.method == 'POST' && path == '/convert/word-to-pdf') {
      await _handleWordToPdf(request);
      return;
    }

    await _sendJson(request.response, {
      'error': 'Not found.',
    }, statusCode: HttpStatus.notFound);
  } catch (error) {
    final statusCode = error is _ClientError
        ? error.statusCode
        : HttpStatus.internalServerError;
    final message = error is _ClientError ? error.message : error.toString();
    await _sendJson(request.response, {
      'error': message,
    }, statusCode: statusCode);
  }
}

void _setCorsHeaders(HttpResponse response) {
  response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'GET,POST,DELETE,OPTIONS')
    ..set(
      'Access-Control-Allow-Headers',
      'Content-Type, X-Requested-With, Access-Control-Request-Private-Network',
    )
    ..set('Access-Control-Allow-Private-Network', 'true')
    ..set('Access-Control-Max-Age', '86400')
    ..set('Access-Control-Expose-Headers', 'Content-Disposition');
}

Future<Map<String, Object>> _healthPayload() async {
  final soffice = await _findExecutable('soffice');
  final tools = <String, Object>{
    'internalPdfText': true,
    'soffice': soffice != null,
  };
  if (soffice != null) {
    tools['sofficePath'] = soffice;
  }

  return {
    'ok': true,
    'tools': tools,
    'features': {
      'pdfToEditableWord': true,
      'wordToPdf': soffice != null,
      'wordToImages': soffice != null,
      'lanTransfer': true,
    },
    'lanUrls': await _localAccessUrls(_serverPort),
    'toolHints': {
      'soffice':
          '可安装 LibreOffice，或设置 COTOOL_SOFFICE，或放到 .cotool_tools/LibreOffice.app/Contents/MacOS/soffice。',
    },
    'missing': [if (soffice == null) 'soffice'],
  };
}

Future<Map<String, Object>> _transferStatusPayload() async {
  return {
    'ok': true,
    'lanUrls': await _localAccessUrls(_serverPort),
    'files': await _transferFiles(),
    'messages': _transferMessagePayloads(),
  };
}

Future<void> _handleTransferUpload(HttpRequest request) async {
  final upload = await _readUpload(request);
  final storedName = _uniqueStoredName(upload.filename);
  final outputFile = File('${_transferDirectory.path}/$storedName');
  await outputFile.writeAsBytes(upload.bytes, flush: true);
  final filePayload = await _transferFilePayload(outputFile);
  await _sendJson(request.response, {'ok': true, 'file': filePayload});
  await _broadcastTransferStatus();
}

Future<void> _handleTransferMessage(HttpRequest request) async {
  final raw = await utf8.decoder.bind(request).join();
  var text = raw;
  try {
    final payload = jsonDecode(raw);
    if (payload is Map<String, dynamic>) {
      text = payload['text']?.toString() ?? '';
    }
  } catch (_) {
    // Plain text is also accepted.
  }

  final sender = request.connectionInfo?.remoteAddress.address ?? 'unknown';
  _addTransferMessage(text, sender: sender);
  await _sendJson(request.response, {
    'ok': true,
    'messages': _transferMessagePayloads(),
  });
  await _broadcastTransferStatus();
}

Future<void> _handleTransferSocket(HttpRequest request) async {
  final sender = request.connectionInfo?.remoteAddress.address ?? 'websocket';
  final socket = await WebSocketTransformer.upgrade(request);
  _transferSockets.add(socket);
  await _sendTransferSocketStatus(socket);
  socket.listen(
    (event) {
      unawaited(_handleTransferSocketEvent(socket, event, sender: sender));
    },
    onDone: () => _transferSockets.remove(socket),
    onError: (_) => _transferSockets.remove(socket),
    cancelOnError: true,
  );
}

Future<void> _handleTransferSocketEvent(
  WebSocket socket,
  dynamic event, {
  required String sender,
}) async {
  if (event is! String) {
    return;
  }

  try {
    final payload = jsonDecode(event);
    if (payload is! Map<String, dynamic>) {
      return;
    }

    final type = payload['type']?.toString();
    if (type == 'message') {
      _addTransferMessage(payload['text']?.toString() ?? '', sender: sender);
      await _broadcastTransferStatus();
      return;
    }

    if (type == 'refresh') {
      await _sendTransferSocketStatus(socket);
    }
  } on _ClientError catch (error) {
    _sendTransferSocketError(socket, error.message);
  } catch (error) {
    _sendTransferSocketError(socket, error.toString());
  }
}

void _addTransferMessage(String text, {required String sender}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw _ClientError('消息不能为空。', HttpStatus.badRequest);
  }

  final now = DateTime.now();
  _transferMessages.add(
    _TransferMessage(
      id: now.microsecondsSinceEpoch.toString(),
      text: trimmed,
      sender: sender,
      createdAt: now,
    ),
  );
}

Future<void> _sendTransferSocketStatus(WebSocket socket) async {
  socket.add(await _transferSocketStatusText());
}

Future<void> _broadcastTransferStatus() async {
  if (_transferSockets.isEmpty) {
    return;
  }

  late final String text;
  try {
    text = await _transferSocketStatusText();
  } catch (_) {
    return;
  }

  final closed = <WebSocket>[];
  for (final socket in _transferSockets) {
    try {
      socket.add(text);
    } catch (_) {
      closed.add(socket);
    }
  }
  _transferSockets.removeAll(closed);
}

Future<String> _transferSocketStatusText() async {
  return jsonEncode({
    'type': 'status',
    'payload': await _transferStatusPayload(),
  });
}

void _sendTransferSocketError(WebSocket socket, String message) {
  try {
    socket.add(jsonEncode({'type': 'error', 'message': message}));
  } catch (_) {
    _transferSockets.remove(socket);
  }
}

List<Map<String, Object>> _transferMessagePayloads() {
  return _transferMessages
      .map(
        (message) => {
          'id': message.id,
          'text': message.text,
          'sender': message.sender,
          'createdAt': message.createdAt.toIso8601String(),
        },
      )
      .toList(growable: false);
}

Future<void> _handleTransferDownload(HttpRequest request) async {
  final id = _pathTail(request.uri.path, '/transfer/download/');
  final file = _transferFileById(id);
  if (!await file.exists()) {
    throw _ClientError('文件不存在。', HttpStatus.notFound);
  }

  await _sendBytes(
    request.response,
    await file.readAsBytes(),
    filename: _displayName(file.uri.pathSegments.last),
    mimeType: _mimeTypeForFilename(file.path),
  );
}

Future<void> _handleTransferDelete(HttpRequest request) async {
  final id = _pathTail(request.uri.path, '/transfer/files/');
  final file = _transferFileById(id);
  if (await file.exists()) {
    await file.delete();
  }
  await _sendJson(request.response, {'ok': true});
  await _broadcastTransferStatus();
}

Future<List<Map<String, Object>>> _transferFiles() async {
  await _transferDirectory.create(recursive: true);
  final files = <File>[];
  await for (final entity in _transferDirectory.list()) {
    if (entity is File) {
      files.add(entity);
    }
  }
  files.sort((a, b) {
    return b.lastModifiedSync().compareTo(a.lastModifiedSync());
  });

  final payloads = <Map<String, Object>>[];
  for (final file in files) {
    payloads.add(await _transferFilePayload(file));
  }
  return payloads;
}

Future<Map<String, Object>> _transferFilePayload(File file) async {
  final stat = await file.stat();
  final id = file.uri.pathSegments.last;
  return {
    'id': id,
    'name': _displayName(id),
    'size': stat.size,
    'modifiedAt': stat.modified.toIso8601String(),
    'downloadUrl': '/transfer/download/${Uri.encodeComponent(id)}',
  };
}

Future<void> _handlePdfToWord(HttpRequest request) async {
  final upload = await _readUpload(request);
  final pages = const PdfTextExtractor()
      .extractPages(upload.bytes)
      .where((page) => page.trim().isNotEmpty)
      .toList();
  if (pages.isEmpty) {
    throw _ClientError(
      '没有提取到可编辑文字。这个 PDF 可能是扫描件，或使用了暂不支持的字体映射，需要 OCR。',
      HttpStatus.unprocessableEntity,
    );
  }

  final outputName = '${_baseName(upload.filename)}.docx';
  final bytes = _textPagesToDocx(pages);
  await _sendBytes(
    request.response,
    bytes,
    filename: outputName,
    mimeType: _docxMimeType,
  );
}

Future<void> _handleWordToPdf(HttpRequest request) async {
  final soffice = await _findExecutable('soffice');
  if (soffice == null) {
    throw _ClientError(
      '缺少 soffice。请安装 LibreOffice 后重启本地转换服务。',
      HttpStatus.serviceUnavailable,
    );
  }

  final upload = await _readUpload(request);
  final tempDir = await Directory.systemTemp.createTemp('cotool-word-pdf-');
  try {
    final extension = _extension(upload.filename, fallback: 'docx');
    final inputFile = File('${tempDir.path}/source.$extension');
    await inputFile.writeAsBytes(upload.bytes, flush: true);

    final result = await Process.run(soffice, [
      '--headless',
      '--convert-to',
      'pdf',
      '--outdir',
      tempDir.path,
      inputFile.path,
    ]);
    if (result.exitCode != 0) {
      throw _ClientError(
        'Word 转 PDF 失败：${_cleanProcessText(result.stderr)}',
        HttpStatus.unprocessableEntity,
      );
    }

    final pdfFile = File('${tempDir.path}/source.pdf');
    if (!await pdfFile.exists()) {
      throw _ClientError(
        'Word 转 PDF 失败：未找到转换后的 PDF 文件。',
        HttpStatus.unprocessableEntity,
      );
    }

    await _sendBytes(
      request.response,
      await pdfFile.readAsBytes(),
      filename: '${_baseName(upload.filename)}.pdf',
      mimeType: 'application/pdf',
    );
  } finally {
    await _deleteTempDir(tempDir);
  }
}

Future<String?> _findExecutable(String executable) async {
  if (executable == 'soffice') {
    return _findSoffice();
  }

  return _findOnPath(executable);
}

Future<String?> _findSoffice() async {
  final envPath = Platform.environment['COTOOL_SOFFICE'];
  if (envPath != null && envPath.trim().isNotEmpty) {
    final file = File(envPath.trim());
    if (await file.exists()) {
      return file.path;
    }
  }

  final cwd = Directory.current.path;
  final candidates = [
    '$cwd/.cotool_tools/soffice',
    '$cwd/.cotool_tools/LibreOffice.app/Contents/MacOS/soffice',
    '$cwd/.cotool_tools/libreoffice/program/soffice',
    '$cwd/.cotool_tools/LibreOffice/program/soffice.exe',
    '/Applications/LibreOffice.app/Contents/MacOS/soffice',
  ];

  for (final candidate in candidates) {
    if (await File(candidate).exists()) {
      return candidate;
    }
  }

  return _findOnPath('soffice');
}

Future<String?> _findOnPath(String executable) async {
  final command = Platform.isWindows ? 'where' : 'which';
  final result = await Process.run(command, [executable]);
  if (result.exitCode != 0) {
    return null;
  }

  final lines = result.stdout
      .toString()
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty);
  return lines.firstOrNull;
}

Future<List<String>> _localAccessUrls(int port) async {
  final urls = <String>['http://127.0.0.1:$port'];
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (address.isLoopback) {
        continue;
      }
      urls.add('http://${address.address}:$port');
    }
  }
  return urls.toSet().toList(growable: false);
}

String _uniqueStoredName(String filename) {
  final safeName = _safeFilename(filename);
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  return '$timestamp-$safeName';
}

String _safeFilename(String filename) {
  final clean = filename.split(RegExp(r'[/\\]')).last.trim();
  final fallback = clean.isEmpty ? 'file' : clean;
  return fallback.replaceAll(RegExp(r'[^\w.\- \u4e00-\u9fa5]'), '_');
}

String _displayName(String storedName) {
  return storedName.replaceFirst(RegExp(r'^\d+-'), '');
}

String _pathTail(String path, String prefix) {
  return Uri.decodeComponent(path.substring(prefix.length));
}

File _transferFileById(String id) {
  final safeId = id.split(RegExp(r'[/\\]')).last;
  return File('${_transferDirectory.path}/$safeId');
}

String _mimeTypeForFilename(String filename) {
  return switch (_extension(filename, fallback: '').toLowerCase()) {
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' => _docxMimeType,
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'txt' => 'text/plain; charset=utf-8',
    'json' => 'application/json; charset=utf-8',
    'zip' => 'application/zip',
    _ => 'application/octet-stream',
  };
}

Future<_UploadedFile> _readUpload(HttpRequest request) async {
  final contentType = request.headers.contentType;
  final boundary = contentType?.parameters['boundary'];
  if (contentType == null ||
      !contentType.mimeType.toLowerCase().contains('multipart/form-data') ||
      boundary == null ||
      boundary.isEmpty) {
    throw _ClientError('请求不是有效的文件上传。', HttpStatus.badRequest);
  }

  final builder = BytesBuilder(copy: false);
  await for (final chunk in request) {
    builder.add(chunk);
  }

  final bytes = builder.takeBytes();
  final body = latin1.decode(bytes, allowInvalid: true);
  final boundaryMarker = '--$boundary';
  final firstBoundary = body.indexOf(boundaryMarker);
  if (firstBoundary < 0) {
    throw _ClientError('上传内容缺少 multipart boundary。', HttpStatus.badRequest);
  }

  final headerStart = firstBoundary + boundaryMarker.length + 2;
  final headerEnd = body.indexOf('\r\n\r\n', headerStart);
  if (headerEnd < 0) {
    throw _ClientError('上传内容缺少文件头。', HttpStatus.badRequest);
  }

  final headers = body.substring(headerStart, headerEnd);
  final filename = _readFilename(headers) ?? 'upload.bin';
  final contentStart = headerEnd + 4;
  final contentEnd = body.indexOf('\r\n$boundaryMarker', contentStart);
  if (contentEnd < 0) {
    throw _ClientError('上传内容缺少文件结尾。', HttpStatus.badRequest);
  }

  final fileBytes = Uint8List.fromList(
    body.substring(contentStart, contentEnd).codeUnits,
  );
  if (fileBytes.isEmpty) {
    throw _ClientError('上传文件为空。', HttpStatus.badRequest);
  }

  return _UploadedFile(filename: filename, bytes: fileBytes);
}

String? _readFilename(String headers) {
  final match = RegExp(r'filename="([^"]*)"').firstMatch(headers);
  final filename = match?.group(1)?.trim();
  if (filename == null || filename.isEmpty) {
    return null;
  }
  return filename.split(RegExp(r'[/\\]')).last;
}

Future<void> _sendJson(
  HttpResponse response,
  Map<String, Object?> payload, {
  int statusCode = HttpStatus.ok,
}) async {
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(payload));
  await response.close();
}

Future<void> _sendHtml(HttpResponse response, String html) async {
  response.statusCode = HttpStatus.ok;
  response.headers.contentType = ContentType.html;
  response.write(html);
  await response.close();
}

Future<void> _sendBytes(
  HttpResponse response,
  Uint8List bytes, {
  required String filename,
  required String mimeType,
}) async {
  response.statusCode = HttpStatus.ok;
  response.headers
    ..contentType = ContentType.parse(mimeType)
    ..set('Content-Disposition', 'attachment; filename="$filename"')
    ..set('Content-Length', bytes.length.toString());
  response.add(bytes);
  await response.close();
}

String _sharePageHtml(HttpRequest request) {
  final requestHost = request.headers.host;
  final host = requestHost == null || requestHost.isEmpty
      ? '127.0.0.1:$_serverPort'
      : requestHost.contains(':')
      ? requestHost
      : '$requestHost:$_serverPort';
  final shareUrl = 'http://$host/share';
  return r'''
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>cotool 局域网传输</title>
  <style>
    :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    * { box-sizing: border-box; }
    body { margin: 0; background: #fffaff; color: #111116; }
    main { min-height: 100svh; max-width: 980px; margin: 0 auto; display: flex; flex-direction: column; background: #fffaff; }
    header { height: 70px; display: grid; grid-template-columns: 52px 1fr 52px; align-items: center; padding: 0 16px; background: #fffaff; }
    h1 { margin: 0; text-align: center; font-size: 24px; font-weight: 900; }
    button { border: 0; background: transparent; color: inherit; cursor: pointer; font: inherit; }
    .icon { width: 42px; height: 42px; border-radius: 999px; display: inline-flex; align-items: center; justify-content: center; color: #77727f; font-size: 24px; }
    .icon:hover { background: #f1ecf9; }
    .messages { flex: 1; overflow-y: auto; padding: 22px 18px 28px; }
    .message-row { display: flex; align-items: center; gap: 8px; margin-bottom: 14px; }
    .message-row.right { justify-content: flex-end; }
    .bubble { max-width: min(620px, 78vw); padding: 16px; border-radius: 16px; background: #eee9fb; overflow-wrap: anywhere; line-height: 1.5; font-size: 17px; }
    .message-row.right .bubble { background: #efb7c5; }
    .message-action { color: #84818a; font-size: 24px; width: 32px; height: 32px; display: inline-flex; align-items: center; justify-content: center; border-radius: 8px; text-decoration: none; }
    .message-action:hover { background: #f1ecf9; }
    .meta { color: #77727f; font-size: 13px; margin-top: 7px; }
    .url { font-weight: 900; font-size: 18px; }
    .qr-box { display: inline-block; margin-top: 14px; padding: 12px; background: #fff; border-radius: 10px; }
    .qr-box svg { display: block; width: min(280px, 68vw); height: auto; }
    .file-name { display: flex; gap: 8px; align-items: flex-start; font-weight: 900; font-size: 17px; }
    .preview { width: min(320px, 66vw); max-height: 260px; object-fit: cover; display: block; border-radius: 8px; margin-bottom: 10px; }
    .bar { height: 7px; border-radius: 999px; background: #d8d0e5; overflow: hidden; margin-top: 12px; }
    .bar span { display: block; width: 100%; height: 100%; background: #c88ea4; }
    .marker { text-align: center; color: #99949f; font-size: 13px; margin: 22px 0; }
    .composer { background: #eee9fb; padding: 12px 16px 16px; display: grid; grid-template-columns: 48px 1fr 58px; gap: 10px; align-items: end; }
    .attach, .send { border-radius: 999px; height: 48px; display: flex; align-items: center; justify-content: center; font-size: 25px; }
    .attach { color: #c6a9ff; }
    .send { height: 58px; background: #cfb6ff; color: #fff; font-size: 30px; }
    textarea { width: 100%; min-height: 48px; max-height: 130px; resize: none; border: 0; outline: none; border-radius: 18px; padding: 14px 16px; font: inherit; background: #fff; }
    .status { color: #817b89; font-size: 13px; min-height: 18px; padding: 0 16px 10px; background: #eee9fb; }
    [hidden] { display: none !important; }
    @media (min-width: 760px) {
      main { min-height: calc(100svh - 48px); margin-top: 24px; margin-bottom: 24px; border: 1px solid #eee8f5; border-radius: 8px; overflow: hidden; box-shadow: 0 18px 46px rgba(24, 18, 30, .08); }
      .messages { padding-left: 30px; padding-right: 30px; }
      .bubble { max-width: 620px; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <button class="icon" id="backButton" title="返回">‹</button>
      <h1>文件共享</h1>
      <button class="icon" id="refreshButton" title="刷新">⟳</button>
    </header>
    <div id="messages" class="messages"></div>
    <div class="composer">
      <button class="attach" id="attachButton" title="发送文件">▧</button>
      <textarea id="messageInput" rows="1" placeholder="输入文字消息"></textarea>
      <button class="send" id="sendMessageButton" title="发送">›</button>
    </div>
    <div id="status" class="status"></div>
    <input id="fileInput" type="file" hidden>
    <template id="qrTemplate">__QR_SVG__</template>
  </main>
  <script>
    const shareUrl = __SHARE_URL_JSON__;
    const fileInput = document.getElementById('fileInput');
    const statusEl = document.getElementById('status');
    const messagesEl = document.getElementById('messages');
    const messageInput = document.getElementById('messageInput');
    const qrTemplate = document.getElementById('qrTemplate');
    let socket;
    let reconnectTimer;

    function formatBytes(bytes) {
      if (bytes < 1024) return bytes + ' B';
      const kb = bytes / 1024;
      if (kb < 1024) return kb.toFixed(1) + ' KB';
      const mb = kb / 1024;
      if (mb < 1024) return mb.toFixed(1) + ' MB';
      return (mb / 1024).toFixed(2) + ' GB';
    }

    function isImageFile(name) {
      return /\.(png|jpg|jpeg|gif|webp)$/i.test(name || '');
    }

    function copyText(text) {
      navigator.clipboard && navigator.clipboard.writeText(text);
      statusEl.textContent = '已复制。';
    }

    function addBubble(options) {
      const row = document.createElement('div');
      row.className = 'message-row' + (options.right ? ' right' : '');
      const bubble = document.createElement('div');
      bubble.className = 'bubble';
      bubble.appendChild(options.content);
      row.appendChild(bubble);
      if (options.actions) {
        for (const action of options.actions) row.appendChild(action);
      }
      messagesEl.appendChild(row);
    }

    function actionButton(label, title, handler) {
      const button = document.createElement('button');
      button.className = 'message-action';
      button.title = title;
      button.textContent = label;
      button.addEventListener('click', handler);
      return button;
    }

    function actionLink(label, title, href) {
      const link = document.createElement('a');
      link.className = 'message-action';
      link.title = title;
      link.textContent = label;
      link.href = href;
      link.download = '';
      return link;
    }

    function textBlock(text, className) {
      const div = document.createElement('div');
      if (className) div.className = className;
      div.textContent = text;
      return div;
    }

    function renderIntro() {
      addBubble({
        content: textBlock('当前窗口可通过以下地址加入，也可以扫码打开。只有同一局域网下的设备能访问。')
      });

      const content = document.createElement('div');
      content.appendChild(textBlock(shareUrl, 'url'));
      const qrBox = document.createElement('div');
      qrBox.className = 'qr-box';
      qrBox.appendChild(qrTemplate.content.cloneNode(true));
      content.appendChild(qrBox);
      addBubble({
        content,
        actions: [actionButton('⧉', '复制地址', () => copyText(shareUrl))]
      });
    }

    function renderMessage(message) {
      const content = document.createElement('div');
      content.appendChild(textBlock(message.text || ''));
      content.appendChild(textBlock((message.sender || 'unknown') + ' · ' + new Date(message.createdAt).toLocaleString(), 'meta'));
      addBubble({ content });
    }

    function renderFile(file) {
      const content = document.createElement('div');
      if (isImageFile(file.name)) {
        const image = document.createElement('img');
        image.className = 'preview';
        image.src = file.downloadUrl;
        image.alt = file.name;
        content.appendChild(image);
      }
      const name = document.createElement('div');
      name.className = 'file-name';
      name.appendChild(textBlock('▧'));
      name.appendChild(textBlock(file.name || 'file'));
      content.appendChild(name);
      const bar = document.createElement('div');
      bar.className = 'bar';
      bar.appendChild(document.createElement('span'));
      content.appendChild(bar);
      content.appendChild(textBlock(formatBytes(file.size || 0) + ' · ' + new Date(file.modifiedAt).toLocaleString(), 'meta'));
      addBubble({
        content,
        actions: [
          actionLink('↓', '下载', file.downloadUrl),
          actionButton('⧉', '复制下载地址', () => copyText(location.origin + file.downloadUrl)),
          actionButton('×', '删除', async () => {
            await fetch('/transfer/files/' + encodeURIComponent(file.id), { method: 'DELETE' });
            requestRefresh();
          })
        ]
      });
    }

    function renderStatus(data) {
      const files = (data.files || []).map((file) => ({ type: 'file', date: file.modifiedAt, value: file }));
      const messages = (data.messages || []).map((message) => ({ type: 'message', date: message.createdAt, value: message }));
      const entries = files.concat(messages).sort((a, b) => new Date(a.date) - new Date(b.date));
      messagesEl.innerHTML = '';
      renderIntro();
      const marker = document.createElement('div');
      marker.className = 'marker';
      marker.textContent = entries.length ? '以上是历史消息' : '暂无传输记录';
      messagesEl.appendChild(marker);
      for (const entry of entries) {
        if (entry.type === 'file') renderFile(entry.value);
        if (entry.type === 'message') renderMessage(entry.value);
      }
      messagesEl.scrollTop = messagesEl.scrollHeight;
    }

    async function refreshStatus() {
      const res = await fetch('/transfer/status');
      const data = await res.json();
      renderStatus(data);
    }

    function sendSocket(payload) {
      if (socket && socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify(payload));
        return true;
      }
      return false;
    }

    function requestRefresh() {
      if (!sendSocket({ type: 'refresh' })) {
        refreshStatus();
      }
    }

    function autoResizeInput() {
      messageInput.style.height = 'auto';
      messageInput.style.height = Math.min(messageInput.scrollHeight, 130) + 'px';
    }

    function connectSocket() {
      if (!('WebSocket' in window)) return;
      const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
      socket = new WebSocket(protocol + '//' + location.host + '/transfer/ws');
      socket.addEventListener('message', (event) => {
        try {
          const data = JSON.parse(event.data);
          if (data.type === 'status') renderStatus(data.payload || {});
          if (data.type === 'error') statusEl.textContent = data.message || '发送失败。';
        } catch (_) {}
      });
      socket.addEventListener('close', () => {
        clearTimeout(reconnectTimer);
        reconnectTimer = setTimeout(connectSocket, 2000);
      });
      socket.addEventListener('error', () => socket.close());
    }

    async function uploadSelectedFile() {
      const file = fileInput.files[0];
      if (!file) {
        statusEl.textContent = '请选择文件。';
        return;
      }
      const form = new FormData();
      form.append('file', file, file.name);
      statusEl.textContent = '正在上传...';
      const res = await fetch('/transfer/upload', { method: 'POST', body: form });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        statusEl.textContent = data.error || '上传失败。';
        return;
      }
      fileInput.value = '';
      statusEl.textContent = '上传完成。';
      requestRefresh();
    }

    async function sendMessage() {
      const text = messageInput.value.trim();
      if (!text) return;
      if (sendSocket({ type: 'message', text })) {
        messageInput.value = '';
        autoResizeInput();
        statusEl.textContent = '文字已发送。';
        return;
      }
      const res = await fetch('/transfer/messages', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text })
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        statusEl.textContent = data.error || '发送失败。';
        return;
      }
      messageInput.value = '';
      autoResizeInput();
      requestRefresh();
    }

    document.getElementById('attachButton').addEventListener('click', () => fileInput.click());
    fileInput.addEventListener('change', uploadSelectedFile);
    document.getElementById('sendMessageButton').addEventListener('click', sendMessage);
    document.getElementById('refreshButton').addEventListener('click', requestRefresh);
    document.getElementById('backButton').addEventListener('click', () => history.back());
    messageInput.addEventListener('input', autoResizeInput);
    messageInput.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' && !event.shiftKey) {
        event.preventDefault();
        sendMessage();
      }
    });
    connectSocket();
    refreshStatus();
  </script>
</body>
</html>
'''
      .replaceAll('__SHARE_URL_JSON__', jsonEncode(shareUrl))
      .replaceAll('__QR_SVG__', _shareQrSvg(shareUrl));
}

String _shareQrSvg(String data) {
  final qrCode = QrCode.fromData(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final image = QrImage(qrCode);
  const quietZone = 4;
  const moduleSize = 6;
  final size = (image.moduleCount + quietZone * 2) * moduleSize;
  final buffer = StringBuffer()
    ..write(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size" role="img" aria-label="局域网传输二维码">',
    )
    ..write('<rect width="$size" height="$size" fill="#fff"/>');

  for (var row = 0; row < image.moduleCount; row++) {
    for (var col = 0; col < image.moduleCount; col++) {
      if (!image.isDark(row, col)) {
        continue;
      }
      final x = (col + quietZone) * moduleSize;
      final y = (row + quietZone) * moduleSize;
      buffer.write(
        '<rect x="$x" y="$y" width="$moduleSize" height="$moduleSize" fill="#000"/>',
      );
    }
  }

  buffer.write('</svg>');
  return buffer.toString();
}

String _baseName(String filename) {
  final clean = filename.split(RegExp(r'[/\\]')).last;
  final dotIndex = clean.lastIndexOf('.');
  if (dotIndex <= 0) {
    return clean.isEmpty ? 'converted' : clean;
  }
  return clean.substring(0, dotIndex);
}

String _extension(String filename, {required String fallback}) {
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == filename.length - 1) {
    return fallback;
  }
  return filename.substring(dotIndex + 1).toLowerCase();
}

String _cleanProcessText(Object value) {
  final text = value.toString().trim();
  return text.isEmpty ? '没有返回错误详情。' : text;
}

Future<void> _deleteTempDir(Directory directory) async {
  try {
    await directory.delete(recursive: true);
  } catch (_) {
    // Best-effort cleanup for local temporary conversion files.
  }
}

Uint8List _textPagesToDocx(List<String> pages) {
  final archive = Archive()
    ..addFile(_textFile('[Content_Types].xml', _contentTypesXml))
    ..addFile(_textFile('_rels/.rels', _rootRelationshipsXml))
    ..addFile(_textFile('word/document.xml', _textDocumentXml(pages)));

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

ArchiveFile _textFile(String path, String content) {
  final bytes = Uint8List.fromList(utf8.encode(content));
  return ArchiveFile(path, bytes.length, bytes);
}

String _textDocumentXml(List<String> pages) {
  final paragraphs = <String>[];
  for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
    final lines = pages[pageIndex].split(RegExp(r'\r?\n'));
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
      <w:pgSz w:w="11906" w:h="16838"/>
      <w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720" w:header="360" w:footer="360" w:gutter="0"/>
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

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

class _UploadedFile {
  const _UploadedFile({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;
}

class _TransferMessage {
  const _TransferMessage({
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

class _ClientError implements Exception {
  const _ClientError(this.message, this.statusCode);

  final String message;
  final int statusCode;
}

const String _contentTypesXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
''';

const String _rootRelationshipsXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
''';
