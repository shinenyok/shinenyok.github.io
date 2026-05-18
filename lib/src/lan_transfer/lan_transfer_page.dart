import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../platform/web_file_actions_stub.dart'
    if (dart.library.html) '../platform/web_file_actions_web.dart';
import '../platform/open_external_stub.dart'
    if (dart.library.html) '../platform/open_external_web.dart';
import 'lan_transfer_client_stub.dart'
    if (dart.library.html) 'lan_transfer_client_web.dart';

const _lanTransferStartCommand = 'dart run tool/local_converter_server.dart';
const _localServerReleaseUrl =
    'https://github.com/shinenyok/shinenyok.github.io/releases/latest';

void _openLocalServerRelease() {
  unawaited(openExternalUrl(_localServerReleaseUrl));
}

class LanTransferPage extends StatefulWidget {
  const LanTransferPage({super.key});

  @override
  State<LanTransferPage> createState() => _LanTransferPageState();
}

class _LanTransferPageState extends State<LanTransferPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<LanTransferStatus>? _statusSubscription;
  LanTransferStatus _status = const LanTransferStatus.offline();
  bool _isRefreshing = false;
  bool _isUploading = false;
  bool _isSendingMessage = false;
  String? _downloadingFileId;

  @override
  void initState() {
    super.initState();
    _connectLiveStatus();
    _refresh();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _connectLiveStatus() {
    _statusSubscription = watchLanTransfer().listen((status) {
      if (!mounted) {
        return;
      }
      setState(() => _status = status);
      _scrollToBottomSoon();
    });
  }

  Future<void> _refresh() async {
    if (_isRefreshing) {
      return;
    }
    setState(() => _isRefreshing = true);
    final status = await probeLanTransfer();
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
      _isRefreshing = false;
    });
    _scrollToBottomSoon();
  }

  Future<void> _upload() async {
    final files = await pickBinaryFiles(accept: '*/*');
    final file = files.firstOrNull;
    if (file == null) {
      return;
    }

    setState(() => _isUploading = true);
    try {
      final status = await uploadLanTransferFile(file);
      if (!mounted) {
        return;
      }
      setState(() => _status = status);
      _showMessage('上传完成。');
      _scrollToBottomSoon();
    } on LanTransferException catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _delete(LanTransferFile file) async {
    try {
      final status = await deleteLanTransferFile(file.id);
      if (!mounted) {
        return;
      }
      setState(() => _status = status);
      _showMessage('已删除。');
    } on LanTransferException catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _download(LanTransferFile file) async {
    setState(() => _downloadingFileId = file.id);
    try {
      final downloaded = await downloadLanTransferFile(file);
      await saveBinaryFile(
        bytes: downloaded.bytes,
        filename: downloaded.name,
        fileExtension: _fileExtension(downloaded.name),
        mimeType: downloaded.mimeType,
      );
      _showMessage('下载完成。');
    } on LanTransferException catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _downloadingFileId = null);
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() => _isSendingMessage = true);
    try {
      final status = await sendLanTransferMessage(text);
      if (!mounted) {
        return;
      }
      _messageController.clear();
      setState(() => _status = status);
      _scrollToBottomSoon();
    } on LanTransferException catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) {
        setState(() => _isSendingMessage = false);
      }
    }
  }

  Future<void> _copyText(String text, {String message = '已复制。'}) async {
    await Clipboard.setData(ClipboardData(text: text));
    _showMessage(message);
  }

  Future<void> _copyStartCommand() async {
    await _copyText(_lanTransferStartCommand, message: '已复制 Dart 启动命令。');
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isCompactPage = MediaQuery.sizeOf(context).width < 560;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isCompactPage ? 12 : 24,
        isCompactPage ? 12 : 20,
        isCompactPage ? 12 : 24,
        40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 940;
              final isCompact = constraints.maxWidth < 560;
              final chatHeight = isWide ? 620.0 : (isCompact ? 560.0 : 680.0);

              final chat = SizedBox(
                height: chatHeight,
                child: _LanChatShell(
                  status: _status,
                  controller: _messageController,
                  scrollController: _scrollController,
                  isRefreshing: _isRefreshing,
                  isUploading: _isUploading,
                  isSending: _isSendingMessage,
                  downloadingFileId: _downloadingFileId,
                  showShareIntro: !isWide,
                  onRefresh: _refresh,
                  onUpload: _upload,
                  onSend: _sendMessage,
                  onCopyText: _copyText,
                  onCopyStartCommand: _copyStartCommand,
                  onDownload: _download,
                  onDelete: _delete,
                ),
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _LanTransferHeader(),
                  const SizedBox(height: 20),
                  if (isWide)
                    SizedBox(
                      height: chatHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 340,
                            child: _DesktopShareRail(
                              status: _status,
                              isRefreshing: _isRefreshing,
                              onRefresh: _refresh,
                              onCopyText: _copyText,
                              onCopyStartCommand: _copyStartCommand,
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(child: chat),
                        ],
                      ),
                    )
                  else
                    chat,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LanTransferHeader extends StatelessWidget {
  const _LanTransferHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xff1f8a70),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.lan, color: Colors.white),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '局域网传输',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '同一 Wi-Fi 下像聊天一样传文字和文件',
                style: TextStyle(color: Color(0xff65736e)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopShareRail extends StatelessWidget {
  const _DesktopShareRail({
    required this.status,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onCopyText,
    required this.onCopyStartCommand,
  });

  final LanTransferStatus status;
  final bool isRefreshing;
  final VoidCallback onRefresh;
  final Future<void> Function(String text, {String message}) onCopyText;
  final VoidCallback onCopyStartCommand;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '扫码加入',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              _ConnectionDot(isRunning: status.isRunning),
              IconButton(
                tooltip: '刷新',
                onPressed: isRefreshing ? null : onRefresh,
                icon: isRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: status.isRunning
                ? _DesktopQrPanel(status: status, onCopyText: onCopyText)
                : _DesktopStartPanel(
                    onCopyStartCommand: onCopyStartCommand,
                    onRefresh: onRefresh,
                  ),
          ),
        ],
      ),
    );
  }
}

class _DesktopQrPanel extends StatelessWidget {
  const _DesktopQrPanel({required this.status, required this.onCopyText});

  final LanTransferStatus status;
  final Future<void> Function(String text, {String message}) onCopyText;

  @override
  Widget build(BuildContext context) {
    if (status.lanUrls.isEmpty) {
      return const Center(
        child: Text(
          '暂未获取到共享地址',
          style: TextStyle(
            color: Color(0xff65736e),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    final primaryUrl = _preferredLanUrl(status.lanUrls);
    final otherUrls = status.lanUrls.where((url) => url != primaryUrl).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final qrSize = (constraints.maxWidth - 36).clamp(150.0, 220.0);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                '手机与电脑连接同一 Wi-Fi 后扫码打开',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xff65736e),
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xfffffbff),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xffeee8f5)),
                ),
                child: QrImageView(
                  data: primaryUrl,
                  version: QrVersions.auto,
                  size: qrSize,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(
                primaryUrl,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => onCopyText(primaryUrl, message: '已复制共享地址。'),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('复制地址'),
                ),
              ),
              if (otherUrls.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '其他入口',
                    style: TextStyle(
                      color: Color(0xff65736e),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...otherUrls.map(
                  (url) => _RailUrlRow(
                    url: url,
                    onCopy: () => onCopyText(url, message: '已复制共享地址。'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DesktopStartPanel extends StatelessWidget {
  const _DesktopStartPanel({
    required this.onCopyStartCommand,
    required this.onRefresh,
  });

  final VoidCallback onCopyStartCommand;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '本地传输服务还没有连接。没有 Dart 环境时，下载本地助手运行后刷新。',
            style: TextStyle(
              color: Color(0xff65736e),
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openLocalServerRelease,
              icon: const Icon(Icons.download_outlined),
              label: const Text('下载本地助手'),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '开发者命令',
            style: TextStyle(
              color: Color(0xff65736e),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xfffffbff),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xffeee8f5)),
            ),
            child: const SelectableText(
              _lanTransferStartCommand,
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCopyStartCommand,
              icon: const Icon(Icons.play_arrow),
              label: const Text('复制 Dart 命令'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新状态'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailUrlRow extends StatelessWidget {
  const _RailUrlRow({required this.url, required this.onCopy});

  final String url;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xfffffbff),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffeee8f5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              url,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: '复制地址',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}

class _LanChatShell extends StatelessWidget {
  const _LanChatShell({
    required this.status,
    required this.controller,
    required this.scrollController,
    required this.isRefreshing,
    required this.isUploading,
    required this.isSending,
    required this.downloadingFileId,
    required this.showShareIntro,
    required this.onRefresh,
    required this.onUpload,
    required this.onSend,
    required this.onCopyText,
    required this.onCopyStartCommand,
    required this.onDownload,
    required this.onDelete,
  });

  final LanTransferStatus status;
  final TextEditingController controller;
  final ScrollController scrollController;
  final bool isRefreshing;
  final bool isUploading;
  final bool isSending;
  final String? downloadingFileId;
  final bool showShareIntro;
  final VoidCallback onRefresh;
  final VoidCallback onUpload;
  final VoidCallback onSend;
  final Future<void> Function(String text, {String message}) onCopyText;
  final VoidCallback onCopyStartCommand;
  final ValueChanged<LanTransferFile> onDownload;
  final ValueChanged<LanTransferFile> onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e5dc)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _ChatTopBar(
            isRunning: status.isRunning,
            isRefreshing: isRefreshing,
            onRefresh: onRefresh,
          ),
          Expanded(
            child: _ChatTimeline(
              status: status,
              scrollController: scrollController,
              downloadingFileId: downloadingFileId,
              showShareIntro: showShareIntro,
              onRefresh: onRefresh,
              onCopyText: onCopyText,
              onCopyStartCommand: onCopyStartCommand,
              onDownload: onDownload,
              onDelete: onDelete,
            ),
          ),
          _ChatComposer(
            controller: controller,
            enabled: status.isRunning,
            isUploading: isUploading,
            isSending: isSending,
            onUpload: onUpload,
            onSend: onSend,
          ),
        ],
      ),
    );
  }
}

class _ChatTopBar extends StatelessWidget {
  const _ChatTopBar({
    required this.isRunning,
    required this.isRefreshing,
    required this.onRefresh,
  });

  final bool isRunning;
  final bool isRefreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final isCompact = _isCompactScreen(context);
    return Container(
      height: isCompact ? 56 : 64,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 10 : 18),
      color: const Color(0xfffbf8fd),
      child: Row(
        children: [
          const Icon(Icons.arrow_back, color: Color(0xff59595f)),
          SizedBox(width: isCompact ? 6 : 12),
          Expanded(
            child: Center(
              child: Text(
                '文件共享',
                style: TextStyle(
                  fontSize: isCompact ? 18 : 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          _ConnectionDot(isRunning: isRunning),
          IconButton(
            tooltip: '刷新',
            onPressed: isRefreshing ? null : onRefresh,
            icon: isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.isRunning});

  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isRunning ? '本地服务已连接' : '本地服务未连接',
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: isRunning ? const Color(0xff1f8a70) : const Color(0xffd18a00),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _ChatTimeline extends StatelessWidget {
  const _ChatTimeline({
    required this.status,
    required this.scrollController,
    required this.downloadingFileId,
    required this.showShareIntro,
    required this.onRefresh,
    required this.onCopyText,
    required this.onCopyStartCommand,
    required this.onDownload,
    required this.onDelete,
  });

  final LanTransferStatus status;
  final ScrollController scrollController;
  final String? downloadingFileId;
  final bool showShareIntro;
  final VoidCallback onRefresh;
  final Future<void> Function(String text, {String message}) onCopyText;
  final VoidCallback onCopyStartCommand;
  final ValueChanged<LanTransferFile> onDownload;
  final ValueChanged<LanTransferFile> onDelete;

  @override
  Widget build(BuildContext context) {
    final entries = _timelineEntries(status);
    final isCompact = _isCompactScreen(context);
    return Container(
      color: const Color(0xfffffbff),
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(
          isCompact ? 10 : 18,
          isCompact ? 14 : 20,
          isCompact ? 10 : 18,
          26,
        ),
        children: [
          if (!status.isRunning && showShareIntro)
            _StartServiceBubble(
              onRefresh: onRefresh,
              onCopyStartCommand: onCopyStartCommand,
            )
          else if (!status.isRunning)
            const _InlineHint(text: '左侧启动本地服务后，就可以在这里传文字和文件。')
          else if (showShareIntro) ...[
            _InfoBubble(
              text: '当前窗口可通过以下地址加入，也可以扫码打开。只有同一局域网下的设备能访问。',
              onCopy: null,
            ),
            const SizedBox(height: 12),
            _ShareUrlBubble(urls: status.lanUrls, onCopyText: onCopyText),
          ],
          if (entries.isNotEmpty) ...[
            const _HistoryMarker(),
            ...entries.map((entry) {
              if (entry.message != null) {
                return _TextMessageBubble(message: entry.message!);
              }
              final file = entry.file!;
              return _FileMessageBubble(
                file: file,
                isDownloading: downloadingFileId == file.id,
                onDownload: () => onDownload(file),
                onDelete: () => onDelete(file),
                onCopy: () =>
                    onCopyText(file.downloadUrl, message: '已复制文件下载地址。'),
              );
            }),
          ] else if (status.isRunning) ...[
            const _HistoryMarker(),
            const Center(
              child: Text(
                '暂无传输记录',
                style: TextStyle(
                  color: Color(0xff8c8d93),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<_TimelineEntry> _timelineEntries(LanTransferStatus status) {
    final entries = <_TimelineEntry>[
      ...status.messages.map(_TimelineEntry.message),
      ...status.files.map(_TimelineEntry.file),
    ];
    entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return entries;
  }
}

class _StartServiceBubble extends StatelessWidget {
  const _StartServiceBubble({
    required this.onRefresh,
    required this.onCopyStartCommand,
  });

  final VoidCallback onRefresh;
  final VoidCallback onCopyStartCommand;

  @override
  Widget build(BuildContext context) {
    final isCompact = _isCompactScreen(context);
    return _ChatBubble(
      maxWidth: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isCompact
                ? '手机网页不能启动电脑上的传输服务。请在电脑打开本站，下载并运行本地助手，再用电脑页面的二维码进入。'
                : '本地传输服务还没有连接。可以下载本地助手运行；开发者也可以复制 Dart 命令到终端。',
            style: TextStyle(fontSize: isCompact ? 15 : 16, height: 1.5),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openLocalServerRelease,
              icon: const Icon(Icons.download_outlined),
              label: const Text('下载本地助手'),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                _lanTransferStartCommand,
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (isCompact) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCopyStartCommand,
                icon: const Icon(Icons.play_arrow),
                label: const Text('复制 Dart 命令'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新状态'),
              ),
            ),
          ] else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: onCopyStartCommand,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('复制 Dart 命令'),
                ),
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新状态'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _InfoBubble extends StatelessWidget {
  const _InfoBubble({required this.text, required this.onCopy});

  final String text;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return _ChatBubble(
      trailing: onCopy == null
          ? null
          : IconButton(
              tooltip: '复制',
              onPressed: onCopy,
              icon: const Icon(Icons.copy_outlined),
            ),
      child: SelectableText(
        text,
        style: const TextStyle(fontSize: 16, height: 1.55),
      ),
    );
  }
}

class _ShareUrlBubble extends StatelessWidget {
  const _ShareUrlBubble({required this.urls, required this.onCopyText});

  final List<String> urls;
  final Future<void> Function(String text, {String message}) onCopyText;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return const _ChatBubble(
        child: Text(
          '暂未获取到共享地址，请刷新服务状态。',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      );
    }

    final primaryUrl = _preferredLanUrl(urls);
    final otherUrls = urls.where((url) => url != primaryUrl).toList();
    final isCompact = _isCompactScreen(context);
    final qrSize = MediaQuery.sizeOf(context).width < 460 ? 184.0 : 220.0;

    return _ChatBubble(
      maxWidth: 640,
      trailing: IconButton(
        tooltip: '复制地址',
        onPressed: () => onCopyText(primaryUrl, message: '已复制共享地址。'),
        icon: const Icon(Icons.copy_outlined),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            primaryUrl,
            style: TextStyle(
              fontSize: isCompact ? 15 : 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: QrImageView(
              data: primaryUrl,
              version: QrVersions.auto,
              size: qrSize,
              backgroundColor: Colors.white,
            ),
          ),
          if (otherUrls.isNotEmpty) ...[
            const SizedBox(height: 14),
            ...otherUrls.map(
              (url) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CompactUrlRow(
                  url: url,
                  onCopy: () => onCopyText(url, message: '已复制共享地址。'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactUrlRow extends StatelessWidget {
  const _CompactUrlRow({required this.url, required this.onCopy});

  final String url;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SelectableText(
            url,
            style: const TextStyle(
              color: Color(0xff656371),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          tooltip: '复制地址',
          onPressed: onCopy,
          icon: const Icon(Icons.copy_outlined, size: 20),
        ),
      ],
    );
  }
}

class _TextMessageBubble extends StatelessWidget {
  const _TextMessageBubble({required this.message});

  final LanTransferMessage message;

  @override
  Widget build(BuildContext context) {
    final outgoing = _isLocalSender(message.sender);
    return _ChatBubble(
      outgoing: outgoing,
      color: outgoing ? const Color(0xffefb7c5) : const Color(0xffeee9fb),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            message.text,
            style: const TextStyle(fontSize: 16, height: 1.45),
          ),
          const SizedBox(height: 7),
          Text(
            '${message.sender} · ${_formatDate(message.createdAt)}',
            style: const TextStyle(color: Color(0xff76727e), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _FileMessageBubble extends StatelessWidget {
  const _FileMessageBubble({
    required this.file,
    required this.isDownloading,
    required this.onDownload,
    required this.onDelete,
    required this.onCopy,
  });

  final LanTransferFile file;
  final bool isDownloading;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final isCompact = _isCompactScreen(context);
    return _ChatBubble(
      maxWidth: isCompact ? 420 : 520,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '下载',
            onPressed: isDownloading ? null : onDownload,
            icon: isDownloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
          ),
          IconButton(
            tooltip: '复制下载地址',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_outlined),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isImageFile(file.name)) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                file.downloadUrl,
                width: double.infinity,
                height: isCompact ? 160 : 210,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  file.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: 1,
              minHeight: 7,
              backgroundColor: const Color(0xffd6d0e4),
              color: const Color(0xffc891a6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatBytes(file.size)} · ${_formatDate(file.modifiedAt)}',
            style: const TextStyle(color: Color(0xff76727e), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.child,
    this.trailing,
    this.outgoing = false,
    this.maxWidth = 480,
    this.color = const Color(0xffeee9fb),
  });

  final Widget child;
  final Widget? trailing;
  final bool outgoing;
  final double maxWidth;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final reservedWidth = trailing == null ? 0.0 : 54.0;
        final availableWidth = math.max(
          180.0,
          constraints.maxWidth - reservedWidth,
        );
        final effectiveMaxWidth = math.min(maxWidth, availableWidth);
        final bubble = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: EdgeInsets.all(_isCompactScreen(context) ? 14 : 16),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: child,
          ),
        );

        return Row(
          mainAxisAlignment: outgoing
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (outgoing) const Spacer(),
            Flexible(child: bubble),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            if (!outgoing) const Spacer(),
          ],
        );
      },
    );
  }
}

class _HistoryMarker extends StatelessWidget {
  const _HistoryMarker();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          '以上是历史消息',
          style: TextStyle(color: Color(0xff8c8d93), fontSize: 12),
        ),
      ),
    );
  }
}

class _InlineHint extends StatelessWidget {
  const _InlineHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xff8c8d93),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.enabled,
    required this.isUploading,
    required this.isSending,
    required this.onUpload,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isUploading;
  final bool isSending;
  final VoidCallback onUpload;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final isCompact = _isCompactScreen(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 10 : 18,
        12,
        isCompact ? 10 : 18,
        16,
      ),
      color: const Color(0xffeee9fb),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton.filledTonal(
            tooltip: '发送文件',
            onPressed: enabled && !isUploading ? onUpload : null,
            icon: isUploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.note_add_outlined),
          ),
          SizedBox(width: isCompact ? 6 : 10),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled && !isSending,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                if (enabled && !isSending) {
                  onSend();
                }
              },
              decoration: InputDecoration(
                hintText: enabled ? '输入文字消息' : '请先启动本地服务',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(width: isCompact ? 6 : 10),
          SizedBox(
            width: isCompact ? 48 : 56,
            height: isCompact ? 48 : 56,
            child: IconButton.filled(
              tooltip: '发送文字',
              onPressed: enabled && !isSending ? onSend : null,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xffcfb6ff),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xffd9d2e8),
              ),
              icon: isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.send, size: isCompact ? 26 : 30),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEntry {
  const _TimelineEntry._({required this.createdAt, this.message, this.file});

  factory _TimelineEntry.message(LanTransferMessage message) {
    return _TimelineEntry._(createdAt: message.createdAt, message: message);
  }

  factory _TimelineEntry.file(LanTransferFile file) {
    return _TimelineEntry._(createdAt: file.modifiedAt, file: file);
  }

  final DateTime createdAt;
  final LanTransferMessage? message;
  final LanTransferFile? file;
}

String _preferredLanUrl(List<String> urls) {
  for (final url in urls) {
    final host = Uri.tryParse(url)?.host;
    if (host != null && host != '127.0.0.1' && host != 'localhost') {
      return url;
    }
  }
  return urls.first;
}

bool _isLocalSender(String sender) {
  return sender == '127.0.0.1' ||
      sender == '::1' ||
      sender == 'localhost' ||
      sender.startsWith('127.');
}

bool _isImageFile(String filename) {
  return switch (_fileExtension(filename)) {
    'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' => true,
    _ => false,
  };
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }
  final mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(1)} MB';
  }
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} GB';
}

String _formatDate(DateTime date) {
  if (date.millisecondsSinceEpoch == 0) {
    return '-';
  }
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}

String _fileExtension(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == filename.length - 1) {
    return 'bin';
  }
  return filename.substring(dotIndex + 1).toLowerCase();
}

bool _isCompactScreen(BuildContext context) {
  return MediaQuery.sizeOf(context).width < 560;
}
