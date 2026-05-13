import 'dart:io';
import 'package:path/path.dart' as p;

import 'utils.dart';
import 'lib/config.dart';
import 'lib/models.dart';
import 'lib/pixiv_api.dart';
import 'lib/ugoira.dart';
import 'lib/telegraph_api.dart';
import 'lib/telegram_api.dart';
import 'lib/notifier.dart';

// ── Delays ──

const _photoDelay = Duration(seconds: 5);
const _rateLimitDelay = Duration(seconds: 15);
const _ugoiraGroupDelay = Duration(seconds: 16);

// ── Markers ──

const _defaultSign = '▎';
const _shortcutSign = '⇪';

// ── Only illust types 0 and 1 are actual illustrations (not manga/ugoira) ──
const _illustrationTypes = {0, 1};

// ============================================================================
//  Entry
// ============================================================================

Future<void> main() async {
  final msgId1 = await handleIllustrationRanking();
  final msgId2 = await handleUgoiraRanking();

  await Future.delayed(_rateLimitDelay);
  await pushShortcut(
    [msgId1, msgId2],
    ['插画排行 Illustration Shortcut', '动图排行 GIF Shortcut'],
  );

  cleanupTmpDirs();
  await barkSuccess();
}

// ============================================================================
//  Illustration ranking
// ============================================================================

Future<int?> handleIllustrationRanking() async {
  final rankingData = await fetchIllustrationRanking();
  if (rankingData == null) {
    WRN('Failed to fetch illustration ranking!');
    await barkFail();
    return null;
  }

  final (date, elements) = rankingData;

  // Fetch page URLs for each illustration
  for (final obj in elements) {
    if (_illustrationTypes.contains(obj.illustType)) {
      final pagesData = await getIllustPages(obj.illustId);
      obj.parsePagesData(pagesData);
    }
  }

  await fetchTagsInParallel(elements);

  final msgId = await sendTextMessage('插画排行榜日期：$date');
  await uploadPhotoMessagesList(elements, '插画');
  LOG('Ranking Done.');
  return msgId;
}

/// Upload illustration ranking entries as photo messages.
Future<void> uploadPhotoMessagesList(
  List<PixivIllustrationElement> eles,
  String? kind, {
  bool showRank = true,
  String? comment,
}) async {
  for (var i = 0; i < eles.length; i++) {
    final obj = eles[i];

    if (!_illustrationTypes.contains(obj.illustType)) continue;

    // Publish to Telegraph and get the link back
    final proxyUrls = obj.originalPageUriList
        .map((uri) => Config.proxy + uri)
        .toList();
    final telegraphUrl = await publishToTelegraph(
      '${obj.title} - ${obj.artist}',
      proxyUrls,
    );

    // Build HTML caption
    final caption = buildCaption(
      kind: kind,
      rank: showRank ? i + 1 : null,
      title: obj.title,
      artist: obj.artist,
      tags: obj.tags,
      telegraphUrl: telegraphUrl,
      pixivId: obj.illustId,
      comment: comment,
    );

    await trySendPhotos(obj, i + 1, caption);

    if (i + 1 < eles.length) {
      await Future.delayed(_photoDelay);
    }
  }
}

/// Attempt to send photos to Telegram, falling back to Telegraph-only text.
Future<void> trySendPhotos(
  PixivIllustrationElement obj,
  int rank,
  String caption,
) async {
  // Only try sending photos if the work has ≤10 pages
  if (obj.originalPageUriList.length <= 10) {
    final originalUrls = obj.originalPageUriList
        .map((u) => Config.proxy + u)
        .toList();
    final regularUrls = obj.regularPageUriList
        .map((u) => Config.proxy + u)
        .toList();

    const maxRetries = 5;
    final knownFailCodes = {429, 400, -1, -2};

    var sendFn = sendPhotoGroupViaUrls;
    var currentUrls = originalUrls;
    final attemptResults = <int>[];

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      final resCode = await sendFn(currentUrls, caption: caption);
      attemptResults.add(resCode);

      if (resCode == 1) break; // success

      if (!knownFailCodes.contains(resCode)) {
        WRN('Unknown resCode: $attemptResults, turn to Telegraph!');
        break;
      }

      if (attemptResults.where((c) => c == -2).length == 2) {
        WRN('Photos too big: $attemptResults, turn to Telegraph!');
        break;
      }

      // Apply the retry strategy
      switch (resCode) {
        case 429:
          await Future.delayed(_rateLimitDelay);
          break;
        case 400:
          await Future.delayed(_photoDelay);
          break;
        case -1:
          sendFn = sendPhotoGroupViaDownload;
          break;
        case -2:
          currentUrls = regularUrls;
          break;
      }
    }

    if (attemptResults.last == 1) {
      LOG('Photo message sent successfully. rank[$rank]');
      return;
    }
    WRN('Failed to send photos to Telegram. rank[$rank]');
  }

  // Fallback: send caption as text (with Telegraph link)
  await sendTextMessage(caption);
  LOG('Only Telegraph message sent. rank[$rank]');
}

// ============================================================================
//  Ugoira ranking
// ============================================================================

Future<int?> handleUgoiraRanking() async {
  final ugoiraData = await fetchUgoiraRanking();
  if (ugoiraData == null) {
    WRN('Failed to fetch ugoira ranking!');
    await barkFail();
    return null;
  }

  var (date, elements) = ugoiraData;

  elements = elements.sublist(0, 5);

  await fetchTagsInParallel(elements);

  // Download ugoira as MP4 (2 at a time to limit concurrency)
  final paths = <String?>[];
  const concurrency = 2;
  final queue = List.of(elements);

  while (queue.isNotEmpty) {
    final batch = queue.take(concurrency).toList();
    queue.removeRange(0, batch.length);

    final results = await Future.wait(
      batch.map((e) => downloadUgoiraAsMp4(e.illustId)),
    );
    paths.addAll(results);
  }

  final msgId = await sendTextMessage('动图排行榜日期：$date');
  await uploadUgoiraRanking(date, elements, paths);
  return msgId;
}

/// Upload ugoira ranking as video groups (5 works per message).
Future<void> uploadUgoiraRanking(
  String date,
  List<UgoiraRankingElement> eles,
  List<String?> paths,
) async {
  const groupSize = 5;

  for (var i = 0; i < eles.length; i += groupSize) {
    final end = (i + groupSize < eles.length) ? i + groupSize : eles.length;
    final currentEles = eles.sublist(i, end);
    final currentPaths = paths.sublist(i, end);

    final caption = [
      '动图组 <i>№${i + 1} - №${i + currentEles.length}</i>',
      '<blockquote expandable>${currentEles.map((ele) => '$_defaultSign<a href="https://pixiv.net/i/${ele.illustId}"><b>${escapeHTML(ele.title)}</b></a>\n$_defaultSign#${escapeHTML(ele.artist)}').join('\n\n')}</blockquote>\n',
      '<blockquote expandable>${currentEles.map((ele) => ele.tags.join(' ')).join('\n\n')}</blockquote>',
    ].join();

    final validPaths = <String>[];
    for (var j = 0; j < currentEles.length; j++) {
      final path = currentPaths[j];
      if (path != null && File(path).existsSync()) {
        validPaths.add(path);
      }
    }

    if (validPaths.isNotEmpty) {
      await trySendVideoGroup(validPaths, caption);
    }

    await Future.delayed(_ugoiraGroupDelay);
  }

  LOG('Ugoira Ranking Done.');
}

/// Retry sending video group on rate-limit errors.
Future<void> trySendVideoGroup(List<String> paths, String caption) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    final resCode = await sendVideoGroup(paths, caption: caption);

    if (resCode == 1) {
      LOG('Media group sent successfully. Count: ${paths.length}');
      return;
    } else if (resCode == 400 || resCode == 429) {
      await Future.delayed(_rateLimitDelay);
    } else {
      LOG('Failed to send media group after $attempt tries.');
      return;
    }
  }
}

// ============================================================================
//  Shared helpers
// ============================================================================

/// Fetch translated tags in parallel with concurrency control.
Future<void> fetchTagsInParallel(
  List<dynamic> elements, {
  int concurrency = 10,
}) async {
  const excludedTags = {'GIF', 'R18', 'R-18', '动图', 'Ugoira'};
  const excludedChars = {
    "'",
    '"',
    '\\',
    '/',
    '(',
    ')',
    '（',
    '）',
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

  while (queue.isNotEmpty) {
    final batch = queue.take(concurrency).toList();
    queue.removeRange(0, batch.length);

    final futures = <Future>[];
    for (final re in batch) {
      futures.add(() async {
        final tags = await getIllustTags(re.illustId);
        if (tags != null) {
          re.tags = tags.where((t) => !excludedTags.contains(t)).map((input) {
            if (isNumeric(input)) {
              return '#TAG_$input';
            }
            final buffer = StringBuffer();
            for (final char in input.runes) {
              final charStr = String.fromCharCode(char);
              if (charStr.trim().isEmpty || excludedChars.contains(charStr)) {
                buffer.write('_');
              } else {
                buffer.write(charStr);
              }
            }
            return '#$buffer';
          }).toList();
        }
      }());
    }
    await Future.wait(futures);
  }
}

/// Build HTML caption for an illustration post.
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
    if (rank == null) {
      buffer.write(
        '#$kind\n<blockquote><a href="$telegraphUrl">Telegraph</a></blockquote>\n',
      );
    } else {
      buffer.write(
        '$kind <i>№$rank</i>\n<blockquote><a href="$telegraphUrl">Telegraph</a></blockquote>\n',
      );
    }
  }

  buffer
    ..write(
      '$_defaultSign<a href="https://pixiv.net/i/$pixivId"><b>${escapeHTML(title)}</b></a>\n',
    )
    ..write('$_defaultSign#${escapeHTML(artist)}\n');

  if (tags.isNotEmpty) {
    buffer.write('<blockquote>${tags.join(' ')}</blockquote>');
  }

  if (comment != null) {
    buffer.write('\n$comment');
  }

  return buffer.toString();
}

/// Send shortcut-links pointing at the two ranking messages.
Future<void> pushShortcut(List<int?> msgIds, List<String> names) async {
  final buffer = StringBuffer();

  for (var i = 0; i < msgIds.length; i++) {
    if (msgIds[i] != null) {
      buffer.write(
        '<a href="${Config.chatUrl}${msgIds[i]}"><b>$_shortcutSign ${names[i]}</b></a>\n',
      );
    }
  }

  final timestamp = DateTime.now().toUtc().toString();
  buffer.write('<blockquote><code>UTC $timestamp</code></blockquote>');
  await sendTextMessage(buffer.toString(), showLinkPreview: false);
}

/// Clean up temporary directories from previous runs.
void cleanupTmpDirs() {
  for (final entity in Directory.current.listSync()) {
    final name = p.basename(entity.path);
    if (name.startsWith('temp_') || name.startsWith('PixivRanking_')) {
      try {
        entity.deleteSync(recursive: true);
        LOG('Temp deleted: ${entity.path}');
      } catch (e) {
        WRN('Failed to delete temp: ${entity.path}\n$e');
      }
    }
  }
}
