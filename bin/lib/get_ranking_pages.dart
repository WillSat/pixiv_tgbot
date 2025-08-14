import 'package:dio/dio.dart';
import '../utils.dart';

final dio = Dio(
  BaseOptions(
    headers: {
      'Accept': 'application/json',
      'Accept-Language': 'zh-CN,zh;q=0.7,en-US;q=0.3',
      'Referer': 'https://www.pixiv.net',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:143.0) Gecko/20100101 Firefox/143.0',
      'Cookie': cookie,
    },
  ),
);

Future<Map?> getPages(Dio d, int illustId) async {
  try {
    final response = await dio.get(
      'https://www.pixiv.net/ajax/illust/$illustId/pages?lang=zh',
    );

    return response.data;
  } catch (e) {
    wrn('Failed to request [$illustId]: $e');
    return null;
  }
}
