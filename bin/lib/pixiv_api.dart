import 'package:dio/dio.dart';
import '../utils.dart';
import 'config.dart';
import 'models.dart';

final _dio = Dio(BaseOptions(
  headers: {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:143.0) Gecko/20100101 Firefox/143.0',
    'Accept': 'application/json',
    'Accept-Language': 'zh-CN,zh;q=0.7,en-US;q=0.3',
    'Cookie': Config.cookie,
  },
));

/// Fetch the male R-18 illustration ranking.
///
/// Returns (date, elements) or null on failure.
Future<(String, List<PixivIllustrationElement>)?>
    fetchIllustrationRanking() async {
  try {
    final response = await _dio.get(
      'https://www.pixiv.net/ranking.php?mode=male_r18&content=all&format=json&p=1',
      options: Options(headers: {
        'Referer': 'https://www.pixiv.net/ranking.php?mode=daily_r18',
      }),
    );

    final List? eleList = response.data?['contents'];
    if (eleList == null || eleList.isEmpty) {
      WRN('Fetch ranking failed: empty ranking list!');
      return null;
    }

    return (
      response.data['date'] as String,
      eleList
          .map((e) => PixivIllustrationElement(
                title: e['title'],
                artist: e['user_name'],
                pageCount: int.parse(e['illust_page_count']),
                illustId: e['illust_id'],
                illustType: int.parse(e['illust_type']),
              ))
          .toList(),
    );
  } on DioException catch (e) {
    WRN('Failed to fetch ranking: ${e.response?.statusCode}');
    return null;
  }
}

/// Fetch the daily R-18 ugoira ranking.
///
/// Returns (date, elements) or null on failure.
Future<(String, List<UgoiraRankingElement>)?> fetchUgoiraRanking() async {
  try {
    final response = await _dio.get(
      'https://www.pixiv.net/ranking.php?mode=daily_r18&content=ugoira&format=json',
      options: Options(headers: {
        'Referer': 'https://www.pixiv.net/ranking.php?mode=daily_r18',
      }),
    );

    if (response.statusCode == 200) {
      final data = response.data;
      final List<dynamic> contents = data['contents'] ?? [];

      return (
        data['date'] as String,
        contents.map<UgoiraRankingElement>((item) {
          return UgoiraRankingElement(
            title: item['title'] ?? '',
            artist: item['user_name'] ?? '',
            illustId: item['illust_id'] ?? 0,
            tags: item['tags'] != null
                ? List<String>.from(
                    (item['tags'] as List)
                        .where((t) => t != 'R-18')
                        .map((e) => '#$e'),
                  )
                : <String>[],
          );
        }).toList(),
      );
    } else {
      WRN('Failed to fetch ugoira ranking: ${response.statusCode}');
      return null;
    }
  } on DioException catch (e) {
    WRN('Failed to fetch ugoira ranking: ${e.response?.statusCode}');
    return null;
  } catch (e) {
    WRN('Unhandled exception: $e');
    return null;
  }
}

/// Get page URLs for an illustration.
Future<Map?> getIllustPages(int illustId) async {
  try {
    final response = await _dio.get(
      'https://www.pixiv.net/ajax/illust/$illustId/pages?lang=zh',
      options: Options(headers: {'Referer': 'https://www.pixiv.net'}),
    );
    return response.data;
  } catch (e) {
    WRN('Failed to get pages for illust $illustId: $e');
    return null;
  }
}

/// Get translated tags for an illustration.
Future<List<String>?> getIllustTags(int illustId) async {
  try {
    final response = await _dio.get(
      'https://www.pixiv.net/ajax/illust/$illustId?lang=zh',
      options: Options(headers: {
        'Referer': 'https://www.pixiv.net/artworks/$illustId',
      }),
    );

    if (response.statusCode == 200) {
      final tagsList = response.data['body']?['tags']?['tags'];
      if (tagsList is List) {
        return tagsList
            .map<String>((tag) {
              final translation = tag['translation'];
              if (translation != null && translation['en'] != null) {
                return translation['en'] as String;
              } else if (tag['tag'] != null) {
                return tag['tag'] as String;
              } else {
                return '';
              }
            })
            .where((t) => t.isNotEmpty)
            .toList();
      } else {
        WRN('No tags found for illust $illustId.');
        return null;
      }
    } else {
      WRN('Failed to get tags for illust $illustId: ${response.statusCode}');
      return null;
    }
  } on DioException catch (e) {
    WRN('Failed to get tags for illust $illustId: ${e.response?.statusCode}');
    return null;
  } catch (e) {
    WRN('Unhandled exception: $e');
    return null;
  }
}

/// Get ugoira metadata (zip URL and frame info).
///
/// Returns (zipUrl, frames) or null on failure.
Future<({String zipUrl, List<FrameInfo> frames})?> getUgoiraMeta(
    int illustId) async {
  try {
    final response = await _dio.get(
      'https://www.pixiv.net/ajax/illust/$illustId/ugoira_meta',
      options: Options(headers: {'Referer': 'https://www.pixiv.net'}),
    );

    final meta = response.data;
    if (meta['error'] == true) {
      WRN('Failed to get ugoira metadata for $illustId: ${meta['message']}');
      return null;
    }

    final body = meta['body'];
    return (
      zipUrl: body['originalSrc'] as String,
      frames: (body['frames'] as List)
          .map((f) => FrameInfo(file: f['file'], delay: f['delay']))
          .toList(),
    );
  } catch (e) {
    WRN('Failed to get ugoira metadata for $illustId: $e');
    return null;
  }
}
