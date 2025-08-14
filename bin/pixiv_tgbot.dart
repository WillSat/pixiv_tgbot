import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'utils.dart';
import 'lib/fetch_ranking.dart';
import 'lib/fetch_ugoira_ranking.dart';
import 'lib/get_ugoira_ranking_mp4.dart';
import 'lib/telegraph.dart';
import 'lib/tgbot.dart' as tgbot;

final proxy = File('in/imgProxy.key').readAsStringSync();
const aDelay = Duration(seconds: 8);
const bDelay = Duration(seconds: 25);
const cDelay = Duration(seconds: 4);
final d = Dio();

/// test
// void main() async {
// print(
// await parseAndPublish('test123435', [
// '${proxy}https://i.pximg.net/img-original/img/2025/08/07/00/00/43/133571574_p0.jpg',
// '${proxy}https://i.pximg.net/img-original/img/2025/08/07/00/00/43/133571574_p1.jpg',
// '${proxy}https://i.pximg.net/img-original/img/2025/08/07/00/00/43/133571574_p2.jpg',
// '${proxy}https://i.pximg.net/img-original/img/2025/08/07/00/00/43/133571574_p3.jpg',
// '${proxy}https://i.pximg.net/img-original/img/2025/08/07/00/00/43/133571574_p4.jpg',
// '${proxy}https://i.pximg.net/img-original/img/2025/08/07/00/00/43/133571574_p5.jpg',
// ]),
//   );
// }

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

    final mdCaption =
        '\\#综合 \\#NO${i + 1}\n'
        '**${escapeMarkdownV2(obj.title)}**\n'
        '\\#${escapeMarkdownV2(obj.author)}\n'
        '> ${obj.tags.map(escapeMarkdownV2).join(' ')}\n'
        '[PIXIV 链接](https://www.pixiv.net/artworks/${obj.illustId})';

    // [original: 0, regular: 1, small: 2, thumb_mini: 3]
    int size = 0;
    int resCode = 0;

    if (obj.originalPageUriList.length > 10) {
      // Upload to telegraph
      final telegraphUrl = await parseAndPublishTelegraph(
        '${obj.title} - ${obj.author}',
        obj.originalPageUriList.map((e) => proxy + e).toList(),
      );

      if (telegraphUrl != null) {
        final caption =
            '\\#综合 \\#长篇 \\#NO${i + 1}\n'
            '**${escapeMarkdownV2(obj.title)}**\n'
            '\\#${escapeMarkdownV2(obj.author)}\n'
            '> ${obj.tags.map(escapeMarkdownV2).join(' ')}\n'
            '**[Telegraph 链接]($telegraphUrl)**\n'
            '[PIXIV 链接](https://www.pixiv.net/artworks/${obj.illustId})';
        await tgbot.sendTextMessage(caption);
      }
    } else {
      // Upload to telegram
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
            // Too big, upload to telegraph
            final telegraphUrl = await parseAndPublishTelegraph(
              '${obj.title} - ${obj.author}',
              obj.originalPageUriList.map((uri) => proxy + uri).toList(),
            );

            if (telegraphUrl != null) {
              final caption =
                  '\\#综合 \\#NO${i + 1}\n'
                  '**${escapeMarkdownV2(obj.title)}**\n'
                  '\\#${escapeMarkdownV2(obj.author)}\n'
                  '> ${obj.tags.map(escapeMarkdownV2).join(' ')}\n'
                  '**[Telegraph 链接]($telegraphUrl)**\n'
                  '[PIXIV 链接](https://www.pixiv.net/artworks/${obj.illustId})';
              await tgbot.sendTextMessage(caption);
              break;
            }
          }
          size++;
        }
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
