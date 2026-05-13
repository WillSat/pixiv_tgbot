/// Represents a single entry in the Pixiv illustration ranking.
class PixivIllustrationElement {
  final String title;
  final String artist;
  final int illustId;
  final int pageCount;
  final int illustType;

  List<String> tags;
  List<String> originalPageUriList = [];
  List<String> regularPageUriList = [];
  bool gotPagesUri = false;

  PixivIllustrationElement({
    required this.title,
    required this.artist,
    required this.illustId,
    required this.pageCount,
    required this.illustType,
    List<String>? tags,
  }) : tags = tags ?? [];

  /// Parse page API response into URL lists. Returns true if page count matches.
  bool parsePagesData(Map? data) {
    if (data == null) return false;
    final body = data['body'] as List;
    originalPageUriList =
        List<String>.from(body.map((m) => m['urls']['original']));
    regularPageUriList =
        List<String>.from(body.map((m) => m['urls']['regular']));
    gotPagesUri = true;
    return pageCount == originalPageUriList.length;
  }
}

/// Represents a single entry in the Pixiv ugoira (GIF) ranking.
class UgoiraRankingElement {
  final String title;
  final String artist;
  final int illustId;
  List<String> tags;

  UgoiraRankingElement({
    required this.title,
    required this.artist,
    required this.illustId,
    List<String>? tags,
  }) : tags = tags ?? [];
}

/// Frame metadata for a ugoira animation.
class FrameInfo {
  final String file;
  final int delay;
  const FrameInfo({required this.file, required this.delay});
}
