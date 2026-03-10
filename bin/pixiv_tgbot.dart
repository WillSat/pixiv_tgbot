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
const bDelay = Duration(seconds: 12);
const cDelay = Duration(seconds: 10);

// Cloudflare Proxy
// https://******.workers.dev/?url=
final proxy = File('in/imgProxy.key').readAsStringSync();

final dio = Dio();

const defaultSign = '▎';
const linkSign = '■';
const shortcutSign = '⇪';

Future<void> main() async {
  // 插画
  final msgId1 = await handleIllustrationRanking();
  // 动图
  final msgId2 = await handleUgoiraRanking();

  await pushShortcut(
    [msgId1, msgId2],
    ['今日插画榜 Illustration Shortcut', '今日动图榜 GIF Shortcut'],
  );

  // 清理临时文件
  cleanupTmpDirs();
  await barkSuccess();
}

/*
  -----------
  处理插画排行榜
  -----------
*/
Future<int?> handleIllustrationRanking() async {
  final rankingData = await fetchRanking(dio);
  if (rankingData == null) {
    wrn('Failed to fetch illustration ranking!');
    await barkFail();
    return null;
  }

  final (date, elements) = rankingData;

  // for test
  // var (date, elements) = rankingData;
  // elements = elements.sublist(48);
  // for test

  for (int i = 0; i < elements.length; i++) {
    final obj = elements[i];
    await obj.getPagesUri(dio);
  }

  await fetchTagsInParallel(elements);

  final msgId = await sendTextMessage('插画排行榜日期：$date');
  await uploadPhotoMessagesList(elements, '插画');
  log('Ranking Done.');
  return msgId;
}

/// 上传插画排行榜
Future<void> uploadPhotoMessagesList(
  List<PixivIllustrationElement> eles,
  String? kind, {
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
Future<int?> handleUgoiraRanking() async {
  final ugoiraData = await fetchUgoiraRanking(dio);
  if (ugoiraData == null) {
    wrn('Failed to fetch ugoira ranking!');
    await barkFail();
    return null;
  }

  final (date, elements) = ugoiraData;

  // for test
  // var (date, elements) = ugoiraData;
  // elements = elements.sublist(39);
  // for test

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

  final msgId = await sendTextMessage('动图排行榜日期：$date');
  await UploadUgoiraRanking(date, elements, paths);
  return msgId;
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
    // HTML
    '<',
    '>',
    '&',
    '〔',
    '〕',
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
    '•',
    '·',
    '‧',
    '・',
    '※',
    '#',
    '?',
    '？',
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

/// 上传动图排行榜（批量分组发送）
Future<void> UploadUgoiraRanking(
  String date,
  List<UgoiraRankingElement> eles,
  List<String?> paths,
) async {
  const int groupSize = 5;

  for (int i = 0; i < eles.length; i += groupSize) {
    // 获取当前分片
    final int end = (i + groupSize < eles.length) ? i + groupSize : eles.length;
    final List<UgoiraRankingElement> currentEles = eles.sublist(i, end);
    final List<String?> currentPaths = paths.sublist(i, end);

    final caption =
        '''动图组 <i>№${i + 1} - №${i + currentEles.length}</i>
<blockquote expandable>${currentEles.map((ele) => '$defaultSign<a href="https://pixiv.net/i/${ele.illustId}"><b>${escapeHTML(ele.title)}</b></a>\n$defaultSign#${escapeHTML(ele.artist)}').join('\n\n')}</blockquote>
<blockquote expandable>${currentEles.map((ele) => ele.tags.join(' ')).join('|')}</blockquote>''';

    final List<String> validPaths = [];
    for (int j = 0; j < currentEles.length; j++) {
      final path = currentPaths[j];

      if (path != null && File(path).existsSync()) {
        validPaths.add(path);
      }
    }

    // 执行批量发送
    if (validPaths.isNotEmpty) {
      await trySendMediaGroup(validPaths, caption);
    }

    await Future.delayed(cDelay);
  }

  log('Ugoira Ranking Done.');
}

/// 尝试发送媒体组到 TG
Future<void> trySendMediaGroup(List<String> paths, String captions) async {
  const maxTries = 3;
  for (int attempt = 0; attempt < maxTries; attempt++) {
    final resCode = await sendMediaGroup(paths, caption: captions);

    if (resCode == 1) {
      log('Media group sent successfully. Count: ${paths.length}');
      return;
    } else if (resCode == 400 || resCode == 429) {
      // 429 是 Too Many Requests
      await Future.delayed(bDelay);
    } else {
      log('Failed to send media group after $attempt tries.');
      return;
    }
  }
}

/// 构建 HTML caption
String buildCaption({
  String? kind,
  required String title,
  required String artist,
  required List<String> tags,
  required int pixivId,
  String? telegraphUrl,
  int? rank,
  String? comment,
}) {
  final buffer = StringBuffer();

  if (kind != null) {
    buffer.write(
      rank == null
          ? '#${kind}・<a href="$telegraphUrl"><b>Telegraph</b></a>\n'
          : '${kind} <i>№${rank}</i>・<a href="$telegraphUrl"><b>Telegraph</b></a>\n',
    );
  }

  buffer
    ..write(
      '$defaultSign<a href="https://pixiv.net/i/$pixivId"><b>${escapeHTML(title)}</b></a>\n',
    )
    ..write('$defaultSign#${escapeHTML(artist)}\n');

  if (tags.length >= 0) {
    buffer.write('<blockquote>${tags.join(' ')}</blockquote>');
  }

  if (comment != null) {
    buffer.write('\n$comment');
  }

  return buffer.toString();
}

Future<void> pushShortcut(List<int?> msgIdList, List<String> nameList) async {
  final chatUrl = File('in/chatUrl.key').readAsStringSync();

  final s = StringBuffer();

  for (var i = 0; i < msgIdList.length; i++) {
    if (msgIdList[0] != null) {
      s.write(
        '<a href="$chatUrl${msgIdList[i]}"><b>$shortcutSign ${nameList[i]}</b></a>\n',
      );
    }
  }

  String timestamp = DateTime.now().toUtc().toString();
  s.write('<blockquote><code>UTC $timestamp</code></blockquote>');
  await sendTextMessage(s.toString(), isShowLinkPreview: false);
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
