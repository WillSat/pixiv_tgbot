import 'dart:io';
import 'package:dio/dio.dart';

import '../lib/config.dart';
import '../lib/models.dart';
import '../lib/pixiv_api.dart';
import '../utils.dart';
import '../pixiv_tgbot.dart';

Future<void> main() async {
  stdout.write('请输入 artworksId: ');
  final artworksId = stdin.readLineSync()?.trim();

  stdout.write('请输入推荐理由: ');
  final reason = stdin.readLineSync()?.trim();

  if (artworksId == null || artworksId.isEmpty) {
    print('错误：未输入 ID');
    return;
  }

  final dio = Dio();

  final response = await dio.get(
    'https://www.pixiv.net/ajax/illust/$artworksId?lang=zh',
    options: Options(
      method: 'GET',
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:143.0) Gecko/20100101 Firefox/143.0',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'Accept-Language': 'zh-CN,zh;q=0.7,en-US;q=0.3',
        'Referer': 'https://www.pixiv.net/artworks/$artworksId',
        'Cookie': Config.cookie,
      },
    ),
  );

  final Map? bodyMap = response.data?['body'];

  if (bodyMap == null || bodyMap.isEmpty) {
    print('未能获取到 body 数据，请确认 ID 是否正确。');
    return;
  }

  final r = PixivIllustrationElement(
    title: bodyMap['title'],
    artist: bodyMap['userName'],
    pageCount: bodyMap['pageCount'],
    illustId: int.tryParse(bodyMap['illustId'] ?? artworksId)!,
    illustType: int.parse(bodyMap['illust_type']),
    tags: [],
  );

  final pagesData = await getIllustPages(r.illustId);
  r.parsePagesData(pagesData);

  await fetchTagsInParallel([r]);

  await uploadPhotoMessagesList(
    [r],
    null,
    showRank: false,
    comment: '<blockquote>$reason</blockquote>',
  );

  cleanupTmpDirs();
  LOG('Done.');
}
