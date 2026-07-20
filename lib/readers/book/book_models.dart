import 'dart:convert';

/// Format-owned book locator. DB stores [encode] opaquely.
class BookLocator {
  const BookLocator({
    required this.sectionIndex,
    this.progressInSection = 0,
    this.spineVersion = spineVersionCurrent,
  });

  static const int spineVersionCurrent = 1;

  final int sectionIndex;
  final double progressInSection;
  final int spineVersion;

  Map<String, Object?> toJson() => {
        'sectionIndex': sectionIndex,
        'progressInSection': progressInSection,
        'spineVersion': spineVersion,
      };

  String encode() => jsonEncode(toJson());

  static BookLocator? tryDecode(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final index = map['sectionIndex'];
      if (index is! int) return null;
      final progress = map['progressInSection'];
      final version = map['spineVersion'];
      return BookLocator(
        sectionIndex: index,
        progressInSection: progress is num ? progress.toDouble() : 0,
        spineVersion: version is int ? version : 0,
      );
    } catch (_) {
      return null;
    }
  }

  BookLocator? validated({required int sectionCount}) {
    if (spineVersion != 0 && spineVersion != spineVersionCurrent) {
      return null;
    }
    if (sectionCount <= 0) return null;
    if (sectionIndex < 0 || sectionIndex >= sectionCount) return null;
    return BookLocator(
      sectionIndex: sectionIndex,
      progressInSection: progressInSection.clamp(0.0, 1.0),
      spineVersion: spineVersionCurrent,
    );
  }
}
