import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../platform/web_file_actions_stub.dart'
    if (dart.library.html) '../platform/web_file_actions_web.dart';
import 'icon_target.dart';

class IconForgePage extends StatefulWidget {
  const IconForgePage({super.key});

  @override
  State<IconForgePage> createState() => _IconForgePageState();
}

class _IconForgePageState extends State<IconForgePage> {
  Uint8List? _sourceBytes;
  String? _fileName;
  int? _sourceWidth;
  int? _sourceHeight;
  bool _isGenerating = false;
  bool _addRoundedPreview = true;

  static const List<IconTarget> _iosTargets = [
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-20x20@2x.png',
      size: 40,
      label: 'iPhone Notification',
      idiom: 'iphone',
      scale: '2x',
      filename: 'Icon-App-20x20@2x.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-20x20@3x.png',
      size: 60,
      label: 'iPhone Notification',
      idiom: 'iphone',
      scale: '3x',
      filename: 'Icon-App-20x20@3x.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-29x29@2x.png',
      size: 58,
      label: 'iPhone Settings',
      idiom: 'iphone',
      scale: '2x',
      filename: 'Icon-App-29x29@2x.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-29x29@3x.png',
      size: 87,
      label: 'iPhone Settings',
      idiom: 'iphone',
      scale: '3x',
      filename: 'Icon-App-29x29@3x.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-40x40@2x.png',
      size: 80,
      label: 'iPhone Spotlight',
      idiom: 'iphone',
      scale: '2x',
      filename: 'Icon-App-40x40@2x.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-40x40@3x.png',
      size: 120,
      label: 'iPhone Spotlight',
      idiom: 'iphone',
      scale: '3x',
      filename: 'Icon-App-40x40@3x.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-60x60@2x.png',
      size: 120,
      label: 'iPhone App',
      idiom: 'iphone',
      scale: '2x',
      filename: 'Icon-App-60x60@2x.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-60x60@3x.png',
      size: 180,
      label: 'iPhone App',
      idiom: 'iphone',
      scale: '3x',
      filename: 'Icon-App-60x60@3x.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-20x20@1x.png',
      size: 20,
      label: 'iPad Notification',
      idiom: 'ipad',
      scale: '1x',
      filename: 'Icon-App-20x20@1x.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-20x20@2x-ipad.png',
      size: 40,
      label: 'iPad Notification',
      idiom: 'ipad',
      scale: '2x',
      filename: 'Icon-App-20x20@2x-ipad.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-29x29@1x.png',
      size: 29,
      label: 'iPad Settings',
      idiom: 'ipad',
      scale: '1x',
      filename: 'Icon-App-29x29@1x.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-29x29@2x-ipad.png',
      size: 58,
      label: 'iPad Settings',
      idiom: 'ipad',
      scale: '2x',
      filename: 'Icon-App-29x29@2x-ipad.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-40x40@1x.png',
      size: 40,
      label: 'iPad Spotlight',
      idiom: 'ipad',
      scale: '1x',
      filename: 'Icon-App-40x40@1x.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-40x40@2x-ipad.png',
      size: 80,
      label: 'iPad Spotlight',
      idiom: 'ipad',
      scale: '2x',
      filename: 'Icon-App-40x40@2x-ipad.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-76x76@1x.png',
      size: 76,
      label: 'iPad App',
      idiom: 'ipad',
      scale: '1x',
      filename: 'Icon-App-76x76@1x.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-76x76@2x.png',
      size: 152,
      label: 'iPad App',
      idiom: 'ipad',
      scale: '2x',
      filename: 'Icon-App-76x76@2x.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png',
      size: 167,
      label: 'iPad Pro App',
      idiom: 'ipad',
      scale: '2x',
      filename: 'Icon-App-83.5x83.5@2x.png',
    ),
    IconTarget(
      path: 'ios/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
      size: 1024,
      label: 'App Store',
      idiom: 'ios-marketing',
      scale: '1x',
      filename: 'Icon-App-1024x1024@1x.png',
    ),
  ];

  static const List<IconTarget> _androidTargets = [
    IconTarget(
      path: 'android/res/mipmap-mdpi/ic_launcher.png',
      size: 48,
      label: 'mdpi',
    ),
    IconTarget(
      path: 'android/res/mipmap-hdpi/ic_launcher.png',
      size: 72,
      label: 'hdpi',
    ),
    IconTarget(
      path: 'android/res/mipmap-xhdpi/ic_launcher.png',
      size: 96,
      label: 'xhdpi',
    ),
    IconTarget(
      path: 'android/res/mipmap-xxhdpi/ic_launcher.png',
      size: 144,
      label: 'xxhdpi',
    ),
    IconTarget(
      path: 'android/res/mipmap-xxxhdpi/ic_launcher.png',
      size: 192,
      label: 'xxxhdpi',
    ),
    IconTarget(
      path: 'android/play-store-icon.png',
      size: 512,
      label: 'Google Play',
    ),
  ];

  Future<void> _pickImage() async {
    PickedImageFile? picked;
    try {
      picked = await pickImageFile();
    } catch (_) {
      _showMessage('图片读取失败，请重新选择一张 PNG、JPG 或 WebP。');
      return;
    }

    if (picked == null) {
      return;
    }
    final selected = picked;

    final decoded = img.decodeImage(selected.bytes);
    if (decoded == null) {
      _showMessage('图片解析失败，请确认文件格式正确。');
      return;
    }

    setState(() {
      _sourceBytes = selected.bytes;
      _fileName = selected.name;
      _sourceWidth = decoded.width;
      _sourceHeight = decoded.height;
    });
  }

  Future<void> _downloadZip() async {
    final sourceBytes = _sourceBytes;
    if (sourceBytes == null) {
      _showMessage('请先上传一张图片。');
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final source = img.decodeImage(sourceBytes);
      if (source == null) {
        _showMessage('图片解析失败，请换一张图片。');
        return;
      }

      final square = _centerCropSquare(source);
      final archive = Archive();
      for (final target in [..._iosTargets, ..._androidTargets]) {
        final resized = img.copyResize(
          square,
          width: target.size,
          height: target.size,
          interpolation: img.Interpolation.cubic,
        );
        archive.addFile(
          ArchiveFile(
            target.path,
            img.encodePng(resized).length,
            img.encodePng(resized),
          ),
        );
      }
      archive.addFile(
        ArchiveFile(
          'ios/AppIcon.appiconset/Contents.json',
          _iosContentsJson.length,
          _iosContentsJson.codeUnits,
        ),
      );
      archive.addFile(
        ArchiveFile('README.txt', _readme.length, _readme.codeUnits),
      );

      final zipBytes = ZipEncoder().encode(archive);
      final didSave = await saveZip(
        Uint8List.fromList(zipBytes),
        'app-icons.zip',
      );
      if (didSave) {
        _showMessage('图标包已生成。');
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  img.Image _centerCropSquare(img.Image source) {
    final side = source.width < source.height ? source.width : source.height;
    final x = (source.width - side) ~/ 2;
    final y = (source.height - side) ~/ 2;
    return img.copyCrop(source, x: x, y: y, width: side, height: side);
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
    final hasImage = _sourceBytes != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 920;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                children: [
                  _TopBar(onUpload: _pickImage),
                  const SizedBox(height: 20),
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 11,
                          child: _UploadPanel(
                            bytes: _sourceBytes,
                            fileName: _fileName,
                            sourceSize: _sourceWidth == null
                                ? null
                                : '$_sourceWidth x $_sourceHeight',
                            roundedPreview: _addRoundedPreview,
                            onUpload: _pickImage,
                            onRoundedChanged: (value) =>
                                setState(() => _addRoundedPreview = value),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 10,
                          child: _ExportPanel(
                            hasImage: hasImage,
                            isGenerating: _isGenerating,
                            onDownload: _downloadZip,
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        _UploadPanel(
                          bytes: _sourceBytes,
                          fileName: _fileName,
                          sourceSize: _sourceWidth == null
                              ? null
                              : '$_sourceWidth x $_sourceHeight',
                          roundedPreview: _addRoundedPreview,
                          onUpload: _pickImage,
                          onRoundedChanged: (value) =>
                              setState(() => _addRoundedPreview = value),
                        ),
                        const SizedBox(height: 16),
                        _ExportPanel(
                          hasImage: hasImage,
                          isGenerating: _isGenerating,
                          onDownload: _downloadZip,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onUpload});

  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xff1f8a70),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.apps, color: Colors.white),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App Icon Forge',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '上传一张源图，导出 iOS 与 Android 图标资源包',
                    style: TextStyle(color: Color(0xff65736e)),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.upload_file),
              label: const Text('上传图片'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadPanel extends StatelessWidget {
  const _UploadPanel({
    required this.bytes,
    required this.fileName,
    required this.sourceSize,
    required this.roundedPreview,
    required this.onUpload,
    required this.onRoundedChanged,
  });

  final Uint8List? bytes;
  final String? fileName;
  final String? sourceSize;
  final bool roundedPreview;
  final VoidCallback onUpload;
  final ValueChanged<bool> onRoundedChanged;

  @override
  Widget build(BuildContext context) {
    final imageBytes = bytes;
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
          const Text(
            '源图片',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onUpload,
            child: Container(
              width: double.infinity,
              height: 360,
              decoration: BoxDecoration(
                color: const Color(0xfff3f5ef),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xffd7ded5)),
              ),
              child: imageBytes == null
                  ? const _EmptyUploadState()
                  : Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          roundedPreview ? 42 : 6,
                        ),
                        child: Image.memory(
                          imageBytes,
                          width: 240,
                          height: 240,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _InfoChip(
                icon: Icons.image,
                text: fileName ?? '支持 PNG / JPG / WebP',
              ),
              if (sourceSize != null)
                _InfoChip(icon: Icons.straighten, text: sourceSize!),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: roundedPreview,
            onChanged: onRoundedChanged,
            title: const Text('圆角预览'),
            subtitle: const Text('iOS 实际圆角由系统应用，导出的 PNG 保持方形。'),
          ),
        ],
      ),
    );
  }
}

class _EmptyUploadState extends StatelessWidget {
  const _EmptyUploadState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_outlined, size: 54),
        SizedBox(height: 14),
        Text(
          '点击选择图片',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 6),
        Text(
          '建议使用 1024 x 1024 或更大的正方形图片',
          style: TextStyle(color: Color(0xff65736e)),
        ),
      ],
    );
  }
}

class _ExportPanel extends StatelessWidget {
  const _ExportPanel({
    required this.hasImage,
    required this.isGenerating,
    required this.onDownload,
  });

  final bool hasImage;
  final bool isGenerating;
  final VoidCallback onDownload;

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
          const Text(
            '导出资源',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          _TargetGroup(
            title: 'iOS AppIcon.appiconset',
            subtitle: '包含 iPhone、iPad、App Store 所需尺寸与 Contents.json',
            targets: _IconForgePageState._iosTargets,
          ),
          const SizedBox(height: 14),
          _TargetGroup(
            title: 'Android mipmap',
            subtitle: '包含 mdpi 到 xxxhdpi，以及 512px Play Store 图标',
            targets: _IconForgePageState._androidTargets,
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: hasImage && !isGenerating ? onDownload : null,
              icon: isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.archive_outlined),
              label: Text(isGenerating ? '正在生成...' : '保存 ZIP 图标包'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetGroup extends StatelessWidget {
  const _TargetGroup({
    required this.title,
    required this.subtitle,
    required this.targets,
  });

  final String title;
  final String subtitle;
  final List<IconTarget> targets;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xfff8f9f5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe2e6dd)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Color(0xff65736e))),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: targets
                .map((target) => _SizeBadge('${target.size}px'))
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xffedf5f1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xff1f8a70)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SizeBadge extends StatelessWidget {
  const _SizeBadge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xffd9dfd5)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

const String _iosContentsJson = '''
{
  "images": [
    { "size": "20x20", "idiom": "iphone", "filename": "Icon-App-20x20@2x.png", "scale": "2x" },
    { "size": "20x20", "idiom": "iphone", "filename": "Icon-App-20x20@3x.png", "scale": "3x" },
    { "size": "29x29", "idiom": "iphone", "filename": "Icon-App-29x29@2x.png", "scale": "2x" },
    { "size": "29x29", "idiom": "iphone", "filename": "Icon-App-29x29@3x.png", "scale": "3x" },
    { "size": "40x40", "idiom": "iphone", "filename": "Icon-App-40x40@2x.png", "scale": "2x" },
    { "size": "40x40", "idiom": "iphone", "filename": "Icon-App-40x40@3x.png", "scale": "3x" },
    { "size": "60x60", "idiom": "iphone", "filename": "Icon-App-60x60@2x.png", "scale": "2x" },
    { "size": "60x60", "idiom": "iphone", "filename": "Icon-App-60x60@3x.png", "scale": "3x" },
    { "size": "20x20", "idiom": "ipad", "filename": "Icon-App-20x20@1x.png", "scale": "1x" },
    { "size": "20x20", "idiom": "ipad", "filename": "Icon-App-20x20@2x-ipad.png", "scale": "2x" },
    { "size": "29x29", "idiom": "ipad", "filename": "Icon-App-29x29@1x.png", "scale": "1x" },
    { "size": "29x29", "idiom": "ipad", "filename": "Icon-App-29x29@2x-ipad.png", "scale": "2x" },
    { "size": "40x40", "idiom": "ipad", "filename": "Icon-App-40x40@1x.png", "scale": "1x" },
    { "size": "40x40", "idiom": "ipad", "filename": "Icon-App-40x40@2x-ipad.png", "scale": "2x" },
    { "size": "76x76", "idiom": "ipad", "filename": "Icon-App-76x76@1x.png", "scale": "1x" },
    { "size": "76x76", "idiom": "ipad", "filename": "Icon-App-76x76@2x.png", "scale": "2x" },
    { "size": "83.5x83.5", "idiom": "ipad", "filename": "Icon-App-83.5x83.5@2x.png", "scale": "2x" },
    { "size": "1024x1024", "idiom": "ios-marketing", "filename": "Icon-App-1024x1024@1x.png", "scale": "1x" }
  ],
  "info": { "version": 1, "author": "xcode" }
}
''';

const String _readme = '''
App Icon Forge

1. iOS: copy ios/AppIcon.appiconset into Assets.xcassets, or replace your existing AppIcon.appiconset.
2. Android: copy android/res/mipmap-* into app/src/main/res.
3. Source images are center-cropped to a square before resizing.
''';
