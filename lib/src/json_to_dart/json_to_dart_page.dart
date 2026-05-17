import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'json_to_dart_generator.dart';

class JsonToDartPage extends StatefulWidget {
  const JsonToDartPage({super.key});

  @override
  State<JsonToDartPage> createState() => _JsonToDartPageState();
}

class _JsonToDartPageState extends State<JsonToDartPage> {
  final TextEditingController _classNameController = TextEditingController(
    text: 'UserModel',
  );
  final TextEditingController _jsonController = TextEditingController(
    text: _sampleJson,
  );
  final TextEditingController _dartController = TextEditingController();
  final JsonToDartGenerator _generator = JsonToDartGenerator();

  String? _errorText;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _classNameController.dispose();
    _jsonController.dispose();
    _dartController.dispose();
    super.dispose();
  }

  void _generate() {
    try {
      final code = _generator.generate(
        source: _jsonController.text,
        rootClassName: _classNameController.text,
      );
      setState(() {
        _dartController.text = code;
        _errorText = null;
      });
    } catch (error) {
      setState(() {
        _errorText = 'JSON 解析失败：$error';
      });
    }
  }

  Future<void> _copyCode() async {
    if (_dartController.text.trim().isEmpty) {
      _showMessage('没有可复制的 Dart 代码。');
      return;
    }
    await Clipboard.setData(ClipboardData(text: _dartController.text));
    _showMessage('Dart 代码已复制。');
  }

  void _clear() {
    setState(() {
      _jsonController.clear();
      _dartController.clear();
      _errorText = null;
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 940;
              final inputPanel = _JsonInputPanel(
                classNameController: _classNameController,
                jsonController: _jsonController,
                errorText: _errorText,
                onGenerate: _generate,
                onClear: _clear,
              );
              final outputPanel = _DartOutputPanel(
                controller: _dartController,
                onCopy: _copyCode,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _JsonToolHeader(),
                  const SizedBox(height: 20),
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: inputPanel),
                        const SizedBox(width: 20),
                        Expanded(child: outputPanel),
                      ],
                    )
                  else
                    Column(
                      children: [
                        inputPanel,
                        const SizedBox(height: 16),
                        outputPanel,
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

class _JsonToolHeader extends StatelessWidget {
  const _JsonToolHeader();

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
          child: const Icon(Icons.data_object, color: Colors.white),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'JSON 转 Dart',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '粘贴 JSON，生成 Dart Model、fromJson 与 toJson',
                style: TextStyle(color: Color(0xff65736e)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _JsonInputPanel extends StatelessWidget {
  const _JsonInputPanel({
    required this.classNameController,
    required this.jsonController,
    required this.errorText,
    required this.onGenerate,
    required this.onClear,
  });

  final TextEditingController classNameController;
  final TextEditingController jsonController;
  final String? errorText;
  final VoidCallback onGenerate;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _ToolPanel(
      title: '输入 JSON',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: classNameController,
            decoration: const InputDecoration(
              labelText: '根类名',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.title),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: jsonController,
            minLines: 18,
            maxLines: 24,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.45,
            ),
            decoration: InputDecoration(
              alignLabelWithHint: true,
              labelText: 'JSON',
              errorText: errorText,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onGenerate,
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('生成 Dart'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.outlined(
                tooltip: '清空',
                onPressed: onClear,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DartOutputPanel extends StatelessWidget {
  const _DartOutputPanel({required this.controller, required this.onCopy});

  final TextEditingController controller;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return _ToolPanel(
      title: 'Dart 代码',
      trailing: IconButton.outlined(
        tooltip: '复制代码',
        onPressed: onCopy,
        icon: const Icon(Icons.copy),
      ),
      child: TextField(
        controller: controller,
        readOnly: true,
        minLines: 23,
        maxLines: 29,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.45,
        ),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Color(0xfff8f9f5),
        ),
      ),
    );
  }
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

const String _sampleJson = '''
{
  "id": 1001,
  "name": "Song",
  "is_active": true,
  "profile": {
    "avatar_url": "https://example.com/avatar.png",
    "score": 98.5
  },
  "tags": ["Flutter", "iOS"],
  "projects": [
    {
      "title": "App Icon Forge",
      "stars": 12
    }
  ]
}
''';
