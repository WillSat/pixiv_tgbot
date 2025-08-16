import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'utils.dart';
import 'lib/fetch_ranking.dart';
import 'lib/fetch_ugoira_ranking.dart';
import 'lib/get_ugoira_ranking_mp4.dart';
import 'lib/telegraph.dart';
import 'lib/get_tags_translated.dart';
import 'lib/tgbot.dart' as tgbot;

const aDelay = Duration(seconds: 8);
const bDelay = Duration(seconds: 30);
const cDelay = Duration(seconds: 3);
final proxy = File('in/imgProxy.key').readAsStringSync();
final dio = Dio();

Future<void> main() async {
  await handleRanking();
  await handleUgoiraRanking();
  cleanupTmpDirs();
}

/// 处理静态图排行榜
/// ###############
Future<void> handleRanking() async {
  final rankingData = await fetchRanking(dio);
  if (rankingData == null) {
    wrn('Failed to fetch ranking!');
    return;
  }

  final (date, elements) = rankingData;

  await fetchTagsInParallel(elements);
  await startUploadingRanking(date, elements);
}

/// 处理动图排行榜
/// #############
Future<void> handleUgoiraRanking() async {
  final ugoiraData = await fetchUgoiraRanking(dio);
  if (ugoiraData == null) {
    wrn('Failed to fetch ugoira ranking!');
    return;
  }

  final (date, elements) = ugoiraData;

  await fetchTagsInParallel(elements);

  // 同时下载动图（限制并发量）
  final paths = <String?>[];
  final concurrency = 3;
  final queue = List.of(elements);

  while (queue.isNotEmpty) {
    final batch = queue.take(concurrency).toList();
    queue.removeRange(0, batch.length);

    final results = await Future.wait(
      batch.map((ure) => downloadUgoiraAsMp4(ure.illustId.toString())),
    );
    paths.addAll(results);
  }

  await UploadUgoiraRanking(date, elements, paths);
}

// 批量获取翻译标签（并行，并处理标签格式）
Future<void> fetchTagsInParallel(
  List<dynamic> elements, {
  int concurrency = 10,
}) async {
  final queue = List.of(elements);
  final futures = <Future>[];

  while (queue.isNotEmpty) {
    final batch = queue.take(concurrency).toList();
    queue.removeRange(0, batch.length);

    futures.clear();
    for (final re in batch) {
      futures.add(() async {
        final tags = await getTagsTranslated(dio, re.illustId);
        if (tags != null) {
          // 过滤掉 "R-18" 和 "动图"
          final filtered = tags.where((t) => t != 'R-18' && t != '动图').map((t) {
            // 替换特殊字符为下划线
            final sanitized = t.replaceAll(
              RegExp(r'''['"\\\/\(\)（）：\:×!！\-+=,，。.·・\s&#?？<>*~]'''),
              '_',
            );
            return '#$sanitized';
          }).toList();

          re.tags = filtered;
        }
      }());
    }

    await Future.wait(futures);
  }
}

/// 上传静态图排行榜
Future<void> startUploadingRanking(
  String date,
  List<RankingElement> eles,
) async {
  await tgbot.sendTextMessage('综合排行榜日期：$date');

  for (int i = 0; i < eles.length; i++) {
    final obj = eles[i];
    await obj.getPagesUri(dio);

    final mdCaption = buildCaption(
      type: '综合',
      rank: i + 1,
      title: obj.title,
      author: obj.author,
      tags: obj.tags,
      pixivId: obj.illustId,
    );

    if (obj.originalPageUriList.length > 10) {
      // 图片太多 -> Telegraph
      await sendToTelegraph(obj, i + 1, '综合', obj.tags);
    } else {
      await trySendPhotos(obj, i + 1, mdCaption);
    }

    sleep(aDelay);
  }

  log('Ranking Done.');
}

/// 上传动图排行榜
Future<void> UploadUgoiraRanking(
  String date,
  List<UgoiraRankingElement> eles,
  List<String?> paths,
) async {
  await tgbot.sendTextMessage('动图排行榜日期：$date');

  for (int i = 0; i < eles.length; i++) {
    final obj = eles[i];
    final path = paths[i];

    final mdCaption = buildCaption(
      type: '动图',
      rank: i + 1,
      title: obj.title,
      author: obj.author,
      tags: obj.tags,
      pixivId: obj.illustId,
    );

    if (path == null || !File(path).existsSync()) {
      await tgbot.sendTextMessage('（此动图无法上传）\n$mdCaption');
    } else {
      await trySendVideo(path, mdCaption);
    }

    sleep(cDelay);
  }

  log('Ugoira Ranking Done.');
}

/// 尝试发送图片到 TG（带重试逻辑）
Future<void> trySendPhotos(RankingElement obj, int rank, String caption) async {
  final List<List<String>> sizes = [
    obj.originalPageUriList,
    obj.regularPageUriList,
  ];

  for (final sizeList in sizes) {
    const tries = 3;

    for (int attempt = 1; attempt <= tries; attempt++) {
      final resCode = await tgbot.sendPhotoViaUrls(
        sizeList.map((uri) => proxy + uri).toList(),
        caption: caption,
      );

      if (resCode == 1) {
        return;
      } else {
        sleep(bDelay);
      }
    }
  }

  // 如果 original + regular 都失败 -> Telegraph
  await sendToTelegraph(obj, rank, '综合', obj.tags);
}

/// 尝试发送视频到 TG
Future<void> trySendVideo(String path, String caption) async {
  const maxTries = 3;
  for (int attempt = 0; attempt < maxTries; attempt++) {
    final resCode = await tgbot.sendVideo(path, caption: caption);
    if (resCode == 1) return;
    if (resCode == 400 && attempt < maxTries - 1) {
      sleep(bDelay);
    } else {
      await tgbot.sendTextMessage('（动图无法上传）\n$caption');
      return;
    }
  }
}

/// 发送到 Telegraph
Future<void> sendToTelegraph(
  RankingElement obj,
  int rank,
  String type,
  List<String> tags,
) async {
  final telegraphUrl = await parseAndPublishTelegraph(
    '${obj.title} - ${obj.author}',
    obj.originalPageUriList.map((uri) => proxy + uri).toList(),
  );

  if (telegraphUrl != null) {
    final caption = buildCaption(
      type: type,
      rank: rank,
      title: obj.title,
      author: obj.author,
      tags: tags,
      pixivId: obj.illustId,
      telegraphUrl: telegraphUrl,
    );
    await tgbot.sendTextMessage(caption);
  }
}

/// 构建 MarkdownV2 caption
String buildCaption({
  required String type,
  required int rank,
  required String title,
  required String author,
  required List<String> tags,
  required int pixivId,
  String? telegraphUrl,
}) {
  final buffer = StringBuffer()
    ..write('`${type}` _\\#NO${rank}_\n')
    ..write('**${escapeMarkdownV2(title)}**\n')
    ..write('\\#${escapeMarkdownV2(author)}\n')
    ..write('>${tags.map(escapeMarkdownV2).join(' ')}\n\n');

  if (telegraphUrl != null) {
    buffer.write('>[Telegraph 链接]($telegraphUrl)\n\n');
  }
  buffer.write('>[PIXIV 链接](https://www.pixiv.net/artworks/$pixivId)');

  return buffer.toString();
}

/// 清理临时目录
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
