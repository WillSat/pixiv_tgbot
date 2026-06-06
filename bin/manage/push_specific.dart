import 'dart:io';
import 'package:dio/dio.dart';

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

  final response = await pixivDio.get(
    'https://www.pixiv.net/ajax/illust/$artworksId?lang=zh',
    options: Options(
      headers: {'Referer': 'https://www.pixiv.net/artworks/$artworksId'},
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
