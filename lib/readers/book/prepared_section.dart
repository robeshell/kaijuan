/// Prepared spine section ready for rendering by a flutter_html engine.
class PreparedSection {
  const PreparedSection({
    required this.href,
    required this.title,
    required this.html,
    this.sectionStylesheets = const [],
    this.footnotes = const {},
  });

  final String href;
  final String title;
  final String html;

  /// CSS text linked from this section's `<head>` (not package-wide OPF CSS).
  final List<String> sectionStylesheets;

  /// Footnote fragment id → plain text for tap popups.
  final Map<String, String> footnotes;
}
