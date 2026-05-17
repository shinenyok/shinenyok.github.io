class BlogPost {
  const BlogPost({
    required this.title,
    required this.date,
    required this.category,
    required this.slug,
    required this.summary,
    required this.html,
  });

  factory BlogPost.fromJson(Map<String, dynamic> json) {
    return BlogPost(
      title: json['title'] as String,
      date: json['date'] as String,
      category: json['category'] as String,
      slug: json['slug'] as String,
      summary: json['summary'] as String,
      html: json['html'] as String,
    );
  }

  final String title;
  final String date;
  final String category;
  final String slug;
  final String summary;
  final String html;
}
