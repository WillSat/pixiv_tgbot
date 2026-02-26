// waitwill@2025-2026

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'utils.dart';
import 'lib/fetch_ranking.dart';
import 'lib/fetch_ugoira_ranking.dart';
import 'lib/get_ugoira_ranking_mp4.dart';
import 'lib/telegraph.dart';
import 'lib/get_tags_translated.dart';
import 'lib/tgbot.dart';
import 'lib/notify.dart';

const aDelay = Duration(seconds: 4);
const bDelay = Duration(seconds: 15);
const cDelay = Duration(seconds: 2);

// https://******.workers.dev/?url=
final proxy = File('in/imgProxy.key').readAsStringSync();

final dio = Dio();

Future<void> main() async {
  // 插画
  await handleIllustrationRanking();
  // 动图
  await handleUgoiraRanking();

  // 清理临时文件
  cleanupTmpDirs();
  await barkSuccess();
}

/*
  -----------
  处理插画排行榜
  -----------
*/
Future<void> handleIllustrationRanking() async {
  final rankingData = await fetchRanking(dio);
  if (rankingData == null) {
    wrn('Failed to fetch illustration ranking!');
    await barkFail();
    return;
  }

  final (date, elements) = rankingData;

  for (int i = 0; i < elements.length; i++) {
    final obj = elements[i];
    await obj.getPagesUri(dio);
  }

  await fetchTagsInParallel(elements);

  await sendTextMessage('插画排行榜日期：$date');
  await uploadPhotoMessagesList(elements, '插画');
  log('Ranking Done.');
}

/// 上传插画排行榜
Future<void> uploadPhotoMessagesList(
  List<PixivIllustrationElement> eles,
  String kind, {
  bool ifShowRankingNumber = true,
  String? comment,
}) async {
  for (int i = 0; i < eles.length; i++) {
    final obj = eles[i];

    // 发布到 Telegraph 获取返回链接
    final telegraphUrl = await parseAndPublishTelegraph(
      '${obj.title} - ${obj.artist}',
      obj.originalPageUriList.map((uri) => proxy + uri).toList(),
    );

    // 构建文案
    final mdCaption = buildCaption(
      kind: kind,
      rank: ifShowRankingNumber ? i + 1 : null,
      title: obj.title,
      artist: obj.artist,
      tags: obj.tags,
      telegraphUrl: telegraphUrl,
      pixivId: obj.illustId,
      comment: comment,
    );

    // 发送图片消息
    await trySendPhotos(obj, i + 1, mdCaption);

    // 如果列表中存在下一个执行 delay
    if (i + 1 < eles.length) {
      await Future.delayed(aDelay);
    }
  }
}

/// 发送图片
Future<void> trySendPhotos(
  PixivIllustrationElement obj,
  int rank,
  String caption,
) async {
  // 作品拥有十张及以下照片，尝试将原图发送到 Telegram
  if (obj.originalPageUriList.length <= 10) {
    // 发送 Telegram 逻辑
    final originalUrls = obj.originalPageUriList
        .map((uri) => proxy + uri)
        .toList();
    final regularUrls = obj.regularPageUriList
        .map((uri) => proxy + uri)
        .toList();

    const knownFailCodes = [429, 400, -1, -2];
    const maxRetries = 5;
    var sendFn = sendPhotoViaUrls;
    var currentUrls = originalUrls;
    final attemptResults = <int>[];

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      final resCode = await sendFn(currentUrls, caption: caption);
      attemptResults.add(resCode);

      if (resCode == 1) break;

      if (!knownFailCodes.contains(resCode)) {
        wrn('Unknown resCode: $attemptResults, turn to Telegraph!');
        break;
      }

      if (attemptResults.where((i) => i == -2).length == 2) {
        wrn('Photos too big: $attemptResults, turn to Telegraph!');
        break;
      }

      switch (resCode) {
        case 429:
          await Future.delayed(bDelay);
          break;
        case 400:
          await Future.delayed(aDelay);
          break;
        case -1:
          sendFn = sendPhotoViaDownload;
          break;
        case -2:
          currentUrls = regularUrls;
          break;
      }
    }

    if (attemptResults.last == 1) {
      // 成功
      log('Photo message sent successfully. rank[$rank]');
      return null;
    } else {
      // 发送失败，只发布到 Telegraph（if {} 外逻辑）
      wrn('Failed to send photos to Telegram. rank[$rank]');
    }
  }

  // 图片过多 or 发送失败
  await sendTextMessage(caption);
  log('Only Telegraph message sent. rank[$rank]');
}

/*
  -----------
  处理动图排行榜
  -----------
*/
Future<void> handleUgoiraRanking() async {
  final ugoiraData = await fetchUgoiraRanking(dio);
  if (ugoiraData == null) {
    wrn('Failed to fetch ugoira ranking!');
    await barkFail();
    return;
  }

  final (date, elements) = ugoiraData;

  await fetchTagsInParallel(elements);

  // 同时下载动图（限制并发量）
  final paths = <String?>[];
  const concurrency = 2;
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
  const Set<String> excludedTags = {'GIF', 'R18', 'R-18', '动图', 'Ugoira'};
  const Set<String> excludedChars = {
    "'",
    '"',
    '\\',
    '/',
    '(',
    ')',
    '（',
    '）',
    '「',
    '」',
    '『',
    '』',
    '：',
    ':',
    '×',
    '!',
    '！',
    '-',
    '+',
    '=',
    ',',
    '，',
    '。',
    '.',
    '、',
    '·',
    '・',
    '&',
    '#',
    '?',
    '？',
    '<',
    '>',
    '*',
    '~',
    '❤',
    '♡',
    '☆',
    '★',
    '♂',
    '♀',
  };

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
          re.tags = tags.where((t) => !excludedTags.contains(t)).map((input) {
            if (isNumeric(input)) {
              // 纯数字
              return '#TAG_${input.toString()}';
            } else {
              // 剔除特殊字符
              final buffer = StringBuffer();
              for (final char in input.runes) {
                final charStr = String.fromCharCode(char);
                if (charStr.trim().isEmpty || excludedChars.contains(charStr)) {
                  buffer.write('_');
                } else {
                  buffer.write(charStr);
                }
              }
              return '#${buffer.toString()}';
            }
          }).toList();
        }
      }());
    }

    await Future.wait(futures);
  }
}

/// 上传动图排行榜
Future<void> UploadUgoiraRanking(
  String date,
  List<UgoiraRankingElement> eles,
  List<String?> paths,
) async {
  await sendTextMessage('动图排行榜日期：$date');

  for (int i = 0; i < eles.length; i++) {
    final obj = eles[i];
    final path = paths[i];

    final mdCaption = buildCaption(
      kind: '动图',
      rank: i + 1,
      title: obj.title,
      artist: obj.author,
      tags: obj.tags,
      pixivId: obj.illustId,
    );

    if (path == null || !File(path).existsSync()) {
      await sendTextMessage('（此动图无法上传）\n$mdCaption');
    } else {
      await trySendVideo(path, i + 1, mdCaption);
    }

    await Future.delayed(cDelay);
  }

  log('Ugoira Ranking Done.');
}

/// 尝试发送视频到 TG
Future<void> trySendVideo(String path, int rank, String caption) async {
  const maxTries = 3;
  for (int attempt = 0; attempt < maxTries; attempt++) {
    final resCode = await sendVideo(path, caption: caption);
    if (resCode == 1) {
      log('Video message sent. rank[$rank]');
      return;
    } else if (resCode == 400 && attempt < maxTries - 1) {
      await Future.delayed(bDelay);
    } else {
      await sendTextMessage('（动图无法上传）\n$caption');
      return;
    }
  }
}

/// 构建 MarkdownV2 caption
String buildCaption({
  required String kind,
  required String title,
  required String artist,
  required List<String> tags,
  required int pixivId,
  int? rank,
  String? telegraphUrl,
  String? comment,
}) {
  final buffer = StringBuffer()
    ..write(rank == null ? '\\#${kind}\n' : '${kind} _`NO${rank}`_\n')
    ..write('■ *${escapeMarkdownV2(title)}*\n')
    ..write('■ \\#${escapeMarkdownV2(artist)}\n')
    ..write('>${tags.map(escapeMarkdownV2).join(' ')}\n');

  if (telegraphUrl != null) {
    buffer.write('>*[■ Telegraph链接]($telegraphUrl)*\n');
  }
  buffer.write('>*[■ Pixiv链接](https://www.pixiv.net/artworks/$pixivId)*');

  if (comment != null) {
    buffer.write('\n\n$comment');
  }

  return buffer.toString();
}

/// 清理临时目录
void cleanupTmpDirs() {
  for (var entity in Directory.current.listSync()) {
    if (p.basename(entity.path).startsWith('temp_') ||
        p.basename(entity.path).startsWith('PixivRanking_')) {
      try {
        entity.deleteSync(recursive: true);
        log('Temp deleted: ${entity.path}');
      } catch (e) {
        wrn('Failed to delete temp: ${entity.path}\n$e');
      }
    }
  }
}
