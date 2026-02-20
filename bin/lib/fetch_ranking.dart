import 'package:dio/dio.dart';
import '../utils.dart';
import 'get_ranking_pages.dart';

class PixivIllustrationElement {
  PixivIllustrationElement({
    required this.title,
    required this.artist,
    required this.pageCount,
    required this.illustId,
    required this.tags,
  });

  final String title, artist;
  final int illustId, pageCount;
  List<String> tags;

  List<String> originalPageUriList = [];
  List<String> regularPageUriList = [];

  bool gotPagesUri = false;

  Future<bool> getPagesUri(Dio d) async {
    final r = await getPages(d, illustId);
    if (r == null) return false;

    final body = r['body'] as List;

    originalPageUriList = _extractUrls(body, 'original');
    regularPageUriList = _extractUrls(body, 'regular');

    gotPagesUri = true;
    return pageCount == originalPageUriList.length;
  }

  List<String> _extractUrls(List body, String key) {
    return List<String>.from(body.map((m) => m['urls'][key]));
  }

  @override
  String toString() {
    return 'RankingElement('
        'title: $title, '
        'author: $artist, '
        'illustId: $illustId, '
        'pageCount: $pageCount, '
        'tags: $tags, '
        'gotPagesUri: $gotPagesUri'
        ')';
  }
}

Future<(String, List<PixivIllustrationElement>)?> fetchRanking(Dio dio) async {
  try {
    final response = await dio.get(
      'https://www.pixiv.net/ranking.php?mode=daily_r18&p=1&format=json',
      options: Options(
        method: 'GET',
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:143.0) Gecko/20100101 Firefox/143.0',
          'Accept': 'application/json, text/javascript, */*; q=0.01',
          'Accept-Language': 'zh-CN,zh;q=0.7,en-US;q=0.3',
          'Referer': 'https://www.pixiv.net/ranking.php?mode=daily_r18',
          'Cookie': cookie,
        },
      ),
    );

    final List? eleList = response.data?['contents'];

    if (eleList == null || eleList.isEmpty) {
      wrn('Fetch ranking failed: empty ranking list!');
      return null;
    }

    return (
      // ranking date
      response.data['date'] as String,
      // ranking elements
      eleList
          .map(
            (e) => PixivIllustrationElement(
              title: e['title'],
              artist: e['user_name'],
              pageCount: int.parse(e['illust_page_count']),
              illustId: e['illust_id'],
              tags: [],
            ),
          )
          .toList(),
    );
  } catch (e) {
    wrn('Failed to fetch ranking: ${(e as DioException).response?.statusCode}');
    return null;
  }
}
