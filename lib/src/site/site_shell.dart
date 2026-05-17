import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../blog/blog_post.dart';
import '../blog/blog_workspace.dart';
import '../file_converter/file_converter_page.dart';
import '../icon_forge/icon_forge_page.dart';
import '../json_to_dart/json_to_dart_page.dart';
import '../lan_transfer/lan_transfer_page.dart';
import '../platform/open_external_stub.dart'
    if (dart.library.html) '../platform/open_external_web.dart';

enum SiteSection {
  home,
  archive,
  iconForge,
  jsonToDart,
  fileConverter,
  lanTransfer,
}

class SiteShell extends StatefulWidget {
  const SiteShell({super.key});

  @override
  State<SiteShell> createState() => _SiteShellState();
}

class _SiteShellState extends State<SiteShell> {
  SiteSection _section = SiteSection.home;
  BlogPost? _selectedPost;
  late final Future<List<BlogPost>> _posts = _loadPosts();

  Future<List<BlogPost>> _loadPosts() async {
    final raw = await rootBundle.loadString('assets/data/posts.json');
    final items = jsonDecode(raw) as List<dynamic>;
    return items
        .map((item) => BlogPost.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  void _showPost(BlogPost post) {
    setState(() {
      _selectedPost = post;
      _section = SiteSection.home;
    });
  }

  void _showSection(SiteSection section) {
    setState(() {
      _section = section;
      if (section != SiteSection.home) {
        _selectedPost = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const _IcpFooter(),
      body: FutureBuilder<List<BlogPost>>(
        future: _posts,
        builder: (context, snapshot) {
          final posts = snapshot.data ?? const <BlogPost>[];
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _SiteHeader(
                  section: _section,
                  onSectionChanged: _showSection,
                ),
              ),
              if (snapshot.connectionState != ConnectionState.done)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_section == SiteSection.iconForge)
                const SliverToBoxAdapter(child: IconForgePage())
              else if (_section == SiteSection.jsonToDart)
                const SliverToBoxAdapter(child: JsonToDartPage())
              else if (_section == SiteSection.fileConverter)
                const SliverToBoxAdapter(child: FileConverterPage())
              else if (_section == SiteSection.lanTransfer)
                const SliverToBoxAdapter(child: LanTransferPage())
              else
                SliverToBoxAdapter(
                  child: BlogWorkspace(
                    posts: posts,
                    selectedPost: _selectedPost,
                    showArchive: _section == SiteSection.archive,
                    onPostSelected: _showPost,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _IcpFooter extends StatelessWidget {
  const _IcpFooter();

  static const _icpText = '豫ICP备2024047055号-1';
  static const _icpUrl = 'https://beian.miit.gov.cn/';

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xfff7faf5),
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: () => openExternalUrl(_icpUrl),
          child: Container(
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xffe3e8df))),
            ),
            child: const Text(
              _icpText,
              style: TextStyle(
                color: Color(0xff65736e),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SiteHeader extends StatelessWidget {
  const _SiteHeader({required this.section, required this.onSectionChanged});

  final SiteSection section;
  final ValueChanged<SiteSection> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 250,
          width: double.infinity,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/banner.jpg'),
              fit: BoxFit.cover,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '成长历程1996',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Flutter、Dart 与 iOS 开发笔记',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _NavButton(
                            icon: Icons.home_outlined,
                            label: '首页',
                            selected: section == SiteSection.home,
                            onTap: () => onSectionChanged(SiteSection.home),
                          ),
                          _NavButton(
                            icon: Icons.archive_outlined,
                            label: '文章归档',
                            selected: section == SiteSection.archive,
                            onTap: () => onSectionChanged(SiteSection.archive),
                          ),
                          _NavButton(
                            icon: Icons.build_outlined,
                            label: '图标工具',
                            selected: section == SiteSection.iconForge,
                            onTap: () =>
                                onSectionChanged(SiteSection.iconForge),
                          ),
                          _NavButton(
                            icon: Icons.data_object,
                            label: 'JSON 转 Dart',
                            selected: section == SiteSection.jsonToDart,
                            onTap: () =>
                                onSectionChanged(SiteSection.jsonToDart),
                          ),
                          _NavButton(
                            icon: Icons.transform,
                            label: '文件转换',
                            selected: section == SiteSection.fileConverter,
                            onTap: () =>
                                onSectionChanged(SiteSection.fileConverter),
                          ),
                          _NavButton(
                            icon: Icons.lan,
                            label: '局域网传输',
                            selected: section == SiteSection.lanTransfer,
                            onTap: () =>
                                onSectionChanged(SiteSection.lanTransfer),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: selected ? Colors.white : Colors.white70,
        foregroundColor: const Color(0xff173d35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
