import 'package:dio/dio.dart';
import '../utils.dart';

class UgoiraRankingElement {
  UgoiraRankingElement({
    required this.title,
    required this.tags,
    required this.illustId,
    required this.author,
  });

  final String title;
  final String author;
  List<String> tags;
  final int illustId;

  @override
  String toString() {
    return 'UgoiraRankingElement(title: $title, tags: $tags, illustId: $illustId, userName: $author)';
  }
}

Future<(String, List<UgoiraRankingElement>)?> fetchUgoiraRanking(
  Dio dio,
) async {
  const url =
      'https://www.pixiv.net/ranking.php?mode=daily_r18&content=ugoira&format=json';

  try {
    final response = await dio.get(
      url,
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

    if (response.statusCode == 200) {
      final data = response.data;

      final List<dynamic> contents = data['contents'] ?? [];

      return (
        data['date'] as String,
        contents.map<UgoiraRankingElement>((item) {
          return UgoiraRankingElement(
            title: item['title'] ?? '',
            tags: item['tags'] != null
                ? List<String>.from(
                    (item['tags'] as List)
                        .where((t) => t != 'R-18')
                        .map((e) => '#$e'),
                  )
                : <String>[],
            illustId: item['illust_id'] ?? 0,
            author: item['user_name'] ?? '',
          );
        }).toList(),
      );
    } else {
      wrn('Failed to fetch ugoira ranking: ${response.statusCode}');
      return null;
    }
  } catch (e) {
    if (e is DioException) {
      wrn('Failed to fetch ugoira ranking: ${e.response?.statusCode}');
    } else {
      wrn('Unhandled exception: $e');
    }
    return null;
  }
}
