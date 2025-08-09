import 'package:dio/dio.dart';
import '../utils.dart';

Future<Map?> getRanking(Dio dio) async {
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

    return response.data as Map;
  } catch (e) {
    wrn('Request ranking.php failed: $e');
    return null;
  }
}
