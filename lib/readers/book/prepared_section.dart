/// Prepared spine section ready for rendering by a flutter_html engine.
class PreparedSection {
  const PreparedSection({
    required this.href,
    required this.title,
    required this.html,
  });

  final String href;
  final String title;
  final String html;
}
