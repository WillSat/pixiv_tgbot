import 'package:dio/dio.dart';
import '../utils.dart';

Future<List<String>?> getTagsTranslated(Dio dio, int illustId) async {
  final url = 'https://www.pixiv.net/ajax/illust/$illustId?lang=zh';

  try {
    final response = await dio.get(
      url,
      options: Options(
        method: 'GET',
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:143.0) Gecko/20100101 Firefox/143.0',
          'Accept': 'application/json',
          'Accept-Language': 'zh-CN,zh;q=0.7,en-US;q=0.3',
          'Referer': 'https://www.pixiv.net/artworks/$illustId',
          'Cookie': cookie,
        },
      ),
    );

    if (response.statusCode == 200) {
      final data = response.data;
      final tagsList = data['body']?['tags']?['tags'];

      if (tagsList is List) {
        return tagsList
            .map<String>((tag) {
              final translation = tag['translation'];
              if (translation != null && translation['en'] != null) {
                return translation['en'] as String;
              } else if (tag['tag'] != null) {
                return tag['tag'] as String;
              } else {
                return ''; // 或者直接跳过
              }
            })
            .where((t) => t.isNotEmpty)
            .toList();
      } else {
        wrn('No tags found for [$illustId].');
        return null;
      }
    } else {
      wrn('Failed to get translated tags[$illustId]: ${response.statusCode}!');
      return null;
    }
  } catch (e) {
    if (e is DioException) {
      wrn(
        'Failed to get translated tags[$illustId]: ${e.response?.statusCode}!',
      );
    } else {
      wrn('Unhandled exception: $e');
    }
    return null;
  }
}
