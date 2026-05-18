import 'package:flutter/material.dart';

import '../platform/web_file_actions_stub.dart'
    if (dart.library.html) '../platform/web_file_actions_web.dart';
import 'file_converter_service.dart';
import 'local_converter_client_stub.dart'
    if (dart.library.html) 'local_converter_client_web.dart';

enum FileConversionMode {
  imagesToPdf,
  imagesToWord,
  pdfToImages,
  pdfToEditableWord,
  wordToPdf,
  wordToImages,
}

class FileConverterPage extends StatefulWidget {
  const FileConverterPage({super.key});

  @override
  State<FileConverterPage> createState() => _FileConverterPageState();
}

class _FileConverterPageState extends State<FileConverterPage> {
  final FileConverterService _service = FileConverterService();
  FileConversionMode _mode = FileConversionMode.imagesToPdf;
  List<PickedBinaryFile> _files = const [];
  bool _isConverting = false;
  bool _isCheckingLocalConverter = false;
  LocalConverterStatus _localConverterStatus =
      const LocalConverterStatus.offline();

  @override
  void initState() {
    super.initState();
    _refreshLocalConverterStatus();
  }

  String get _accept {
    return switch (_mode) {
      FileConversionMode.imagesToPdf ||
      FileConversionMode.imagesToWord => 'image/png,image/jpeg,image/webp',
      FileConversionMode.pdfToImages ||
      FileConversionMode.pdfToEditableWord => 'application/pdf,.pdf',
      FileConversionMode.wordToPdf || FileConversionMode.wordToImages =>
        '.doc,.docx,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    };
  }

  bool get _allowMultiple {
    return switch (_mode) {
      FileConversionMode.imagesToPdf || FileConversionMode.imagesToWord => true,
      FileConversionMode.pdfToImages ||
      FileConversionMode.pdfToEditableWord ||
      FileConversionMode.wordToPdf ||
      FileConversionMode.wordToImages => false,
    };
  }

  String get _pickLabel {
    return switch (_mode) {
      FileConversionMode.imagesToPdf ||
      FileConversionMode.imagesToWord => '选择图片',
      FileConversionMode.pdfToImages ||
      FileConversionMode.pdfToEditableWord => '选择 PDF',
      FileConversionMode.wordToPdf ||
      FileConversionMode.wordToImages => '选择 Word',
    };
  }

  String get _convertLabel {
    return switch (_mode) {
      FileConversionMode.imagesToPdf => '保存 PDF',
      FileConversionMode.imagesToWord => '保存 Word',
      FileConversionMode.pdfToImages => '保存图片 ZIP',
      FileConversionMode.pdfToEditableWord => '保存可编辑 Word',
      FileConversionMode.wordToPdf => '保存 PDF',
      FileConversionMode.wordToImages => '保存图片 ZIP',
    };
  }

  bool get _localModeReady {
    return switch (_mode) {
      FileConversionMode.wordToPdf => _localConverterStatus.wordToPdf,
      FileConversionMode.wordToImages => _localConverterStatus.wordToImages,
      _ => true,
    };
  }

  Future<void> _pickFiles() async {
    try {
      final files = await pickBinaryFiles(
        accept: _accept,
        multiple: _allowMultiple,
      );
      if (files.isEmpty) {
        return;
      }
      setState(() => _files = files);
    } catch (_) {
      _showMessage('文件读取失败，请重新选择。');
    }
  }

  Future<void> _convert() async {
    if (_files.isEmpty) {
      _showMessage('请先选择文件。');
      return;
    }
    if (_mode.usesLocalConverter && !_localModeReady) {
      await _refreshLocalConverterStatus();
      if (!_localModeReady) {
        _showMessage(_localConverterUnavailableMessage());
        return;
      }
    }

    setState(() => _isConverting = true);
    try {
      switch (_mode) {
        case FileConversionMode.imagesToPdf:
          final bytes = await _service.imagesToPdf(_files);
          await saveBinaryFile(
            bytes: bytes,
            filename: 'images.pdf',
            fileExtension: 'pdf',
            mimeType: 'application/pdf',
          );
        case FileConversionMode.imagesToWord:
          final bytes = await _service.imagesToDocx(_files);
          await saveBinaryFile(
            bytes: bytes,
            filename: 'images.docx',
            fileExtension: 'docx',
            mimeType:
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          );
        case FileConversionMode.pdfToImages:
          final bytes = await _service.pdfToImageZip(_files.first);
          await saveBinaryFile(
            bytes: bytes,
            filename: 'pdf-pages.zip',
            fileExtension: 'zip',
            mimeType: 'application/zip',
          );
        case FileConversionMode.pdfToEditableWord:
          final bytes = await _service.pdfToEditableDocx(_files.first);
          await saveBinaryFile(
            bytes: bytes,
            filename: '${_filenameWithoutExtension(_files.first.name)}.docx',
            fileExtension: 'docx',
            mimeType:
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          );
        case FileConversionMode.wordToPdf:
          final result = await convertWordToPdf(_files.first);
          await saveBinaryFile(
            bytes: result.bytes,
            filename: result.filename,
            fileExtension: 'pdf',
            mimeType: result.mimeType,
          );
        case FileConversionMode.wordToImages:
          final result = await convertWordToPdf(_files.first);
          final bytes = await _service.pdfToImageZip(
            PickedBinaryFile(
              name: result.filename,
              mimeType: 'application/pdf',
              bytes: result.bytes,
            ),
          );
          await saveBinaryFile(
            bytes: bytes,
            filename:
                '${_filenameWithoutExtension(_files.first.name)}-pages.zip',
            fileExtension: 'zip',
            mimeType: 'application/zip',
          );
      }
      _showMessage('转换完成。');
    } on FormatException catch (error) {
      _showMessage(error.message);
    } on LocalConverterException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('转换失败，请确认文件格式正确。');
    } finally {
      if (mounted) {
        setState(() => _isConverting = false);
      }
    }
  }

  void _selectMode(FileConversionMode mode) {
    setState(() {
      _mode = mode;
      _files = const [];
    });
  }

  Future<void> _refreshLocalConverterStatus() async {
    if (_isCheckingLocalConverter) {
      return;
    }
    setState(() => _isCheckingLocalConverter = true);
    final status = await probeLocalConverter();
    if (!mounted) {
      return;
    }
    setState(() {
      _localConverterStatus = status;
      _isCheckingLocalConverter = false;
    });
  }

  String _localConverterUnavailableMessage() {
    if (!_localConverterStatus.isRunning) {
      return '请先下载并运行本地助手；开发者也可运行 dart run tool/local_converter_server.dart';
    }
    if (_localConverterStatus.missingTools.isNotEmpty) {
      return '本地转换服务缺少：${_localConverterStatus.missingTools.join(', ')}';
    }
    return '当前本地转换服务暂不支持这个转换。';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 940;
              final modePanel = _ModePanel(
                selectedMode: _mode,
                onModeSelected: _selectMode,
              );
              final workspace = _ConverterWorkspace(
                mode: _mode,
                files: _files,
                isConverting: _isConverting,
                pickLabel: _pickLabel,
                convertLabel: _convertLabel,
                onPickFiles: _pickFiles,
                onConvert: _convert,
                localConverterStatus: _localConverterStatus,
                isCheckingLocalConverter: _isCheckingLocalConverter,
                onRefreshLocalConverter: _refreshLocalConverterStatus,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _ConverterHeader(),
                  const SizedBox(height: 20),
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 340, child: modePanel),
                        const SizedBox(width: 20),
                        Expanded(child: workspace),
                      ],
                    )
                  else
                    Column(
                      children: [
                        modePanel,
                        const SizedBox(height: 16),
                        workspace,
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ConverterHeader extends StatelessWidget {
  const _ConverterHeader();

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
          child: const Icon(Icons.transform, color: Colors.white),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '文件转换',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '图片、PDF、Word 常用转换',
                style: TextStyle(color: Color(0xff65736e)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModePanel extends StatelessWidget {
  const _ModePanel({required this.selectedMode, required this.onModeSelected});

  final FileConversionMode selectedMode;
  final ValueChanged<FileConversionMode> onModeSelected;

  @override
  Widget build(BuildContext context) {
    return _ToolPanel(
      title: '转换类型',
      child: Column(
        children: [
          _ModeTile(
            icon: Icons.picture_as_pdf_outlined,
            title: '图片转 PDF',
            subtitle: '多张图片合成一个 PDF',
            selected: selectedMode == FileConversionMode.imagesToPdf,
            onTap: () => onModeSelected(FileConversionMode.imagesToPdf),
          ),
          _ModeTile(
            icon: Icons.description_outlined,
            title: '图片转 Word',
            subtitle: '多张图片写入 DOCX',
            selected: selectedMode == FileConversionMode.imagesToWord,
            onTap: () => onModeSelected(FileConversionMode.imagesToWord),
          ),
          _ModeTile(
            icon: Icons.image_outlined,
            title: 'PDF 转图片',
            subtitle: '每页导出为 PNG，并打包 ZIP',
            selected: selectedMode == FileConversionMode.pdfToImages,
            onTap: () => onModeSelected(FileConversionMode.pdfToImages),
          ),
          _ModeTile(
            icon: Icons.edit_document,
            title: 'PDF 转 Word',
            subtitle: '本地提取文字，生成可编辑 DOCX',
            selected: selectedMode == FileConversionMode.pdfToEditableWord,
            onTap: () => onModeSelected(FileConversionMode.pdfToEditableWord),
          ),
          _ModeTile(
            icon: Icons.picture_as_pdf,
            title: 'Word 转 PDF',
            subtitle: '功能暂未开放',
            selected: selectedMode == FileConversionMode.wordToPdf,
            enabled: false,
            onTap: () {},
          ),
          _ModeTile(
            icon: Icons.collections_outlined,
            title: 'Word 转图片',
            subtitle: '功能暂未开放',
            selected: selectedMode == FileConversionMode.wordToImages,
            enabled: false,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _ConverterWorkspace extends StatelessWidget {
  const _ConverterWorkspace({
    required this.mode,
    required this.files,
    required this.isConverting,
    required this.pickLabel,
    required this.convertLabel,
    required this.onPickFiles,
    required this.onConvert,
    required this.localConverterStatus,
    required this.isCheckingLocalConverter,
    required this.onRefreshLocalConverter,
  });

  final FileConversionMode mode;
  final List<PickedBinaryFile> files;
  final bool isConverting;
  final String pickLabel;
  final String convertLabel;
  final VoidCallback onPickFiles;
  final VoidCallback onConvert;
  final LocalConverterStatus localConverterStatus;
  final bool isCheckingLocalConverter;
  final VoidCallback onRefreshLocalConverter;

  @override
  Widget build(BuildContext context) {
    final canConvert =
        files.isNotEmpty &&
        (!mode.usesLocalConverter || mode.canUseLocal(localConverterStatus));
    return _ToolPanel(
      title: '转换工作台',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 230),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xfff8f9f5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xffe2e6dd)),
            ),
            child: files.isEmpty
                ? _EmptyFileState(label: pickLabel)
                : _SelectedFileList(files: files),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isConverting ? null : onPickFiles,
                  icon: const Icon(Icons.upload_file),
                  label: Text(pickLabel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: canConvert && !isConverting ? onConvert : null,
                  icon: isConverting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_alt),
                  label: Text(isConverting ? '正在转换...' : convertLabel),
                ),
              ),
            ],
          ),
          if (mode.usesLocalConverter) ...[
            const SizedBox(height: 14),
            _LocalConverterStatusView(
              mode: mode,
              status: localConverterStatus,
              isChecking: isCheckingLocalConverter,
              onRefresh: onRefreshLocalConverter,
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.58,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xffedf5f1)
                  : const Color(0xfffafbf7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? const Color(0xff1f8a70)
                    : const Color(0xffedf0e8),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xff1f8a70)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xff65736e),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalConverterStatusView extends StatelessWidget {
  const _LocalConverterStatusView({
    required this.mode,
    required this.status,
    required this.isChecking,
    required this.onRefresh,
  });

  final FileConversionMode mode;
  final LocalConverterStatus status;
  final bool isChecking;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final ready = mode.canUseLocal(status);
    final color = ready ? const Color(0xff1f8a70) : const Color(0xffa15c00);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            ready ? Icons.check_circle_outline : Icons.info_outline,
            color: color,
            size: 20,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _localStatusText(mode, status, isChecking),
            style: const TextStyle(color: Color(0xff65736e), height: 1.5),
          ),
        ),
        IconButton(
          tooltip: '刷新本地服务状态',
          onPressed: isChecking ? null : onRefresh,
          icon: isChecking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _EmptyFileState extends StatelessWidget {
  const _EmptyFileState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.file_open_outlined, size: 52),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _SelectedFileList extends StatelessWidget {
  const _SelectedFileList({required this.files});

  final List<PickedBinaryFile> files;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已选择 ${files.length} 个文件',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        ...files.map(
          (file) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatBytes(file.bytes.length),
                  style: const TextStyle(
                    color: Color(0xff65736e),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe0e4dc)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
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
  return '${mb.toStringAsFixed(1)} MB';
}

String _filenameWithoutExtension(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex <= 0) {
    return filename;
  }
  return filename.substring(0, dotIndex);
}

String _localStatusText(
  FileConversionMode mode,
  LocalConverterStatus status,
  bool isChecking,
) {
  if (isChecking) {
    return '正在检测本地转换服务...';
  }
  if (!status.isRunning) {
    return '本地增强服务未连接。下载并运行本地助手后刷新。';
  }
  if (mode.canUseLocal(status)) {
    return '本地增强服务已连接。';
  }
  if (status.missingTools.isNotEmpty) {
    return '本地增强服务已连接，但缺少 ${status.missingTools.join(', ')}。';
  }
  return '本地增强服务已连接，但当前转换不可用。';
}

extension on FileConversionMode {
  bool get usesLocalConverter {
    return switch (this) {
      FileConversionMode.wordToPdf || FileConversionMode.wordToImages => true,
      _ => false,
    };
  }

  bool canUseLocal(LocalConverterStatus status) {
    return switch (this) {
      FileConversionMode.wordToPdf => status.wordToPdf,
      FileConversionMode.wordToImages => status.wordToImages,
      _ => true,
    };
  }
}
