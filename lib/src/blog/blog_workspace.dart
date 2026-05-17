import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import 'blog_post.dart';

class BlogWorkspace extends StatelessWidget {
  const BlogWorkspace({
    super.key,
    required this.posts,
    required this.selectedPost,
    required this.showArchive,
    required this.onPostSelected,
  });

  final List<BlogPost> posts;
  final BlogPost? selectedPost;
  final bool showArchive;
  final ValueChanged<BlogPost> onPostSelected;

  @override
  Widget build(BuildContext context) {
    final activePost = selectedPost ?? (posts.isEmpty ? null : posts.first);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 880) {
                return Column(
                  children: [
                    _PostList(
                      posts: posts,
                      selectedPost: activePost,
                      showArchive: showArchive,
                      onPostSelected: onPostSelected,
                    ),
                    const SizedBox(height: 16),
                    if (activePost != null) _PostReader(post: activePost),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 330,
                    child: _PostList(
                      posts: posts,
                      selectedPost: activePost,
                      showArchive: showArchive,
                      onPostSelected: onPostSelected,
                    ),
                  ),
                  const SizedBox(width: 22),
                  if (activePost != null)
                    Expanded(child: _PostReader(post: activePost)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PostList extends StatelessWidget {
  const _PostList({
    required this.posts,
    required this.selectedPost,
    required this.showArchive,
    required this.onPostSelected,
  });

  final List<BlogPost> posts;
  final BlogPost? selectedPost;
  final bool showArchive;
  final ValueChanged<BlogPost> onPostSelected;

  @override
  Widget build(BuildContext context) {
    final groupedYears = <String, List<BlogPost>>{};
    for (final post in posts) {
      groupedYears.putIfAbsent(post.date.substring(0, 4), () => []).add(post);
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe0e4dc)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            showArchive ? '文章归档' : '最新文章',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          if (showArchive)
            ...groupedYears.entries.map(
              (entry) => _ArchiveYear(
                year: entry.key,
                posts: entry.value,
                selectedPost: selectedPost,
                onPostSelected: onPostSelected,
              ),
            )
          else
            ...posts.map(
              (post) => _PostTile(
                post: post,
                selected: selectedPost?.slug == post.slug,
                onTap: () => onPostSelected(post),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArchiveYear extends StatelessWidget {
  const _ArchiveYear({
    required this.year,
    required this.posts,
    required this.selectedPost,
    required this.onPostSelected,
  });

  final String year;
  final List<BlogPost> posts;
  final BlogPost? selectedPost;
  final ValueChanged<BlogPost> onPostSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            year,
            style: const TextStyle(
              color: Color(0xff1f8a70),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ...posts.map(
            (post) => _PostTile(
              post: post,
              compact: true,
              selected: selectedPost?.slug == post.slug,
              onTap: () => onPostSelected(post),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({
    required this.post,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final BlogPost post;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xffedf5f1) : const Color(0xfffafbf7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xff1f8a70)
                  : const Color(0xffedf0e8),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CategoryPill(post.category),
                  const SizedBox(width: 8),
                  Text(
                    post.date,
                    style: const TextStyle(
                      color: Color(0xff65736e),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                post.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
              if (!compact && post.summary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  post.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff65736e),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PostReader extends StatelessWidget {
  const _PostReader({required this.post});

  final BlogPost post;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe0e4dc)),
      ),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _CategoryPill(post.category),
                Text(
                  post.date,
                  style: const TextStyle(
                    color: Color(0xff65736e),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              post.title,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 16),
            Html(
              data: post.html,
              style: {
                'body': Style(
                  margin: Margins.zero,
                  color: const Color(0xff24322f),
                  fontSize: FontSize(16),
                  lineHeight: const LineHeight(1.7),
                ),
                'h1': Style(
                  fontSize: FontSize(24),
                  fontWeight: FontWeight.w800,
                ),
                'h2': Style(
                  fontSize: FontSize(21),
                  fontWeight: FontWeight.w800,
                ),
                'h3': Style(
                  fontSize: FontSize(18),
                  fontWeight: FontWeight.w800,
                ),
                'p': Style(margin: Margins.only(bottom: 12)),
                'code': Style(
                  backgroundColor: const Color(0xffeef2eb),
                  padding: HtmlPaddings.symmetric(horizontal: 4, vertical: 2),
                ),
                'pre': Style(
                  backgroundColor: const Color(0xff182420),
                  color: Colors.white,
                  padding: HtmlPaddings.all(12),
                ),
                'figure': Style(
                  backgroundColor: const Color(0xff182420),
                  color: Colors.white,
                  padding: HtmlPaddings.all(12),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill(this.category);

  final String category;

  @override
  Widget build(BuildContext context) {
    final isFlutter = category == 'Flutter';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isFlutter ? const Color(0xffe6f2ff) : const Color(0xffffeee8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        category,
        style: TextStyle(
          color: isFlutter ? const Color(0xff1769aa) : const Color(0xffa94c25),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
