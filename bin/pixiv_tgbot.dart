import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'utils.dart';
import 'lib/fetch_ranking.dart';
import 'lib/fetch_ugoira_ranking.dart';
import 'lib/get_ugoira_ranking_mp4.dart';
import 'lib/tgbot.dart' as tgbot;

final proxy = File('in/imgProxy.key').readAsStringSync();
const aDelay = Duration(seconds: 8);
const bDelay = Duration(seconds: 25);
const cDelay = Duration(seconds: 4);
final d = Dio();

void main() async {
  // ranking
  final (String, List<RankingElement>)? r1 = await fetchRanking(d);
  if (r1 != null) {
    await startUploadingRanking(r1.$1, r1.$2);
  } else {
    wrn('Failed to fetch ranking!');
  }

  // ugoira ranking
  final (String, List<UgoiraRankingElement>)? r2 = await fetchUgoiraRanking(d);
  if (r2 != null) {
    // final eleList = r2.$2.sublist(0, 2);
    final eleList = r2.$2;
    final List<String?> paths = [];
    for (final ure in eleList) {
      paths.add(await downloadUgoiraAsMp4(ure.illustId.toString()));
    }

    await startUploadingUgoiraRanking(r2.$1, eleList, paths);

    cleanupTmpDirs();
  } else {
    wrn('Failed to fetch ugoira ranking!');
  }
}

Future<void> startUploadingRanking(
  String date,
  List<RankingElement> eles,
) async {
  await tgbot.sendTextMessage('综合排行榜日期：$date');

  // proxy url update
  for (int i = 0; i < eles.length; i++) {
    final obj = eles[i];
    await obj.getPagesUri(d);

    // [original: 0, regular: 1, small: 2, thumb_mini: 3]
    int size = 0;
    int resCode = 0;

    final mdCaption =
        '\\#综合 \\#NO${i + 1}\n'
        '**${escapeMarkdownV2(obj.title)}**\n'
        '\\#${escapeMarkdownV2(obj.author)}\n'
        '> ${obj.tags.map(escapeMarkdownV2).join(' ')}\n'
        '[PIXIV 链接](https://www.pixiv.net/artworks/${obj.illustId})';

    while (resCode != 1) {
      resCode = await tgbot.sendPhotoViaUrls(
        obj.originalPageUriList.map((uri) => proxy + uri).toList(),
        caption: mdCaption,
      );

      // Punishment
      if (resCode != 1) sleep(bDelay);

      // Handle errors
      if (resCode == 400) {
        if (size < 3) {
          // original: try again
          resCode = await tgbot.sendPhotoViaUrls(
            obj.regularPageUriList.map((uri) => proxy + uri).toList(),
            caption: mdCaption,
          );
        } else if (size < 5) {
          // regular
          resCode = await tgbot.sendPhotoViaUrls(
            obj.regularPageUriList.map((uri) => proxy + uri).toList(),
            caption: mdCaption,
          );
        } else if (size < 6) {
          // small
          resCode = await tgbot.sendPhotoViaUrls(
            obj.smallPageUriList.map((uri) => proxy + uri).toList(),
            caption: mdCaption,
          );
        } else if (size < 7) {
          // thumb_mini
          resCode = await tgbot.sendPhotoViaUrls(
            obj.miniPageUriList.map((uri) => proxy + uri).toList(),
            caption: '（因图片过大，显示缩略图）\n$mdCaption',
          );
        } else {
          // Image too much big
          await tgbot.sendTextMessage('（此图片无法上传）\n$mdCaption');
          break;
        }
        size++;
      }
    }

    sleep(aDelay);
  }

  log('Ranking Done.');
}

Future<void> startUploadingUgoiraRanking(
  String date,
  List<UgoiraRankingElement> eles,
  List<String?> paths,
) async {
  await tgbot.sendTextMessage('动图排行榜日期：$date');

  // proxy url update
  for (int i = 0; i < eles.length; i++) {
    final obj = eles[i];
    final path = paths[i];

    final mdCaption =
        '\\#动图 \\#NO${i + 1}\n'
        '**${escapeMarkdownV2(obj.title)}**\n'
        '\\#${escapeMarkdownV2(obj.author)}\n'
        '> ${obj.tags.map(escapeMarkdownV2).join(' ')}\n'
        '[PIXIV 链接](https://www.pixiv.net/artworks/${obj.illustId})';

    if (path == null || !File(path).existsSync()) {
      // has no mp4
      await tgbot.sendTextMessage('（此动图无法上传）\n$mdCaption');
    } else {
      int tried = 0;
      int resCode = 0;
      while (resCode != 1) {
        resCode = await tgbot.sendVideo(path, caption: mdCaption);

        // Punishment
        if (resCode != 1) sleep(bDelay);

        // Handle errors
        if (resCode == 400) {
          if (tried > 2) {
            await tgbot.sendTextMessage('（动图无法上传）\n$mdCaption');
            break;
          }
          tried++;
        }
      }
    }

    sleep(cDelay);
  }

  log('Ugoira Ranking Done.');
}

void cleanupTmpDirs() {
  for (var entity in Directory.current.listSync()) {
    if (entity is Directory && p.basename(entity.path).startsWith('temp_')) {
      try {
        entity.deleteSync(recursive: true);
        log('Temp dir deleted: ${entity.path}');
      } catch (e) {
        wrn('Failed to delete old temp dir: ${entity.path}\n$e');
      }
    }
  }
}
