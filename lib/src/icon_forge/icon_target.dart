class IconTarget {
  const IconTarget({
    required this.path,
    required this.size,
    required this.label,
    this.idiom,
    this.scale,
    this.filename,
  });

  final String path;
  final int size;
  final String label;
  final String? idiom;
  final String? scale;
  final String? filename;
}
