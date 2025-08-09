import 'dart:io';

import 'package:dio/dio.dart';

import 'utils.dart';
import 'lib/getranking.dart' as getRanking;
import 'lib/getpages.dart' as getPages;
import 'lib/tgbot.dart' as tgbot;

final proxy = File('in/imgProxy.key').readAsStringSync();
const uploadDelay = Duration(seconds: 15);
const punishDelay = Duration(seconds: 30);
final d = Dio();

class RankingElement {
  RankingElement({
    required this.name,
    required this.author,
    required this.pageCount,
    required this.illustId,
  });

  final String name, author;
  final int illustId, pageCount;
  List<String> originalPageUriList = [],
      regulurPageUriList = [],
      smallPageUriList = [],
      miniPageUriList = [];
  bool gotPagesUri = false;

  Future<bool> getPagesUri(Dio d) async {
    final r = await getPages.getPages(d, illustId);
    if (r == null) return false;
    originalPageUriList = (r['body'] as List)
        .map((m) => m['urls']['original'])
        .whereType<String>()
        .toList();

    regulurPageUriList = (r['body'] as List)
        .map((m) => m['urls']['regular'])
        .whereType<String>()
        .toList();

    smallPageUriList = (r['body'] as List)
        .map((m) => m['urls']['small'])
        .whereType<String>()
        .toList();

    miniPageUriList = (r['body'] as List)
        .map((m) => m['urls']['thumb_mini'])
        .whereType<String>()
        .toList();

    return pageCount == originalPageUriList.length;
  }
}

void main() async {
  final rankingMap = await getRanking.getRanking(d);

  final List? eleList = rankingMap?['contents'];
  final String rankingDate = rankingMap!['date'];
  if (eleList == null || eleList.isEmpty) {
    wrn('Get ranking failed: empty ranking list!');
    return;
  }

  final List<RankingElement> objList = eleList
      .map(
        (e) => RankingElement(
          name: e['title'],
          author: e['user_name'],
          pageCount: int.parse(e['illust_page_count']),
          illustId: e['illust_id'],
        ),
      )
      .toList();

  await tgbot.sendTextMessage('排行榜日期：$rankingDate');

  /// proxy url update [√]
  //
  for (int i = 0; i < objList.length; i++) {
    final obj = objList[i];
    await obj.getPagesUri(d);

    int resCode = 0;
    // [original: 0, regular: 1, small: 2, thumb_mini: 3]
    int size = 0;

    while (resCode != 1) {
      resCode = await tgbot.sendPhotoUrls(
        obj.originalPageUriList.map((uri) => proxy + uri).toList(),
        caption:
            '（原图显示）\n$rankingDate #No${i + 1}\n\n> ${obj.name}\n> #${obj.author}\n> ${obj.illustId}\nhttps://www.pixiv.net/artworks/${obj.illustId}',
      );

      // Handle errors
      if (resCode == 429) {
        // Delay punishment
        sleep(punishDelay);
      } else if (resCode == 400) {
        if (size == 0) {
          // regular
          size = 1;
          resCode = await tgbot.sendPhotoUrls(
            obj.regulurPageUriList.map((uri) => proxy + uri).toList(),
            caption:
                '（因图片过大，有压缩）\n$rankingDate #No${i + 1}\n\n> ${obj.name}\n> #${obj.author}\n> ${obj.illustId}\nhttps://www.pixiv.net/artworks/${obj.illustId}',
          );
        } else if (size == 1) {
          // small
          size = 2;
          resCode = await tgbot.sendPhotoUrls(
            obj.smallPageUriList.map((uri) => proxy + uri).toList(),
            caption:
                '（因图片过大，有较大压缩）\n$rankingDate #No${i + 1}\n\n> ${obj.name}\n> #${obj.author}\n> ${obj.illustId}\nhttps://www.pixiv.net/artworks/${obj.illustId}',
          );
        } else if (size == 2) {
          // thumb_mini
          size = 3;
          resCode = await tgbot.sendPhotoUrls(
            obj.miniPageUriList.map((uri) => proxy + uri).toList(),
            caption:
                '（因图片过大，显示缩略图）\n$rankingDate #No${i + 1}\n\n> ${obj.name}\n> #${obj.author}\n> ${obj.illustId}\nhttps://www.pixiv.net/artworks/${obj.illustId}',
          );
        } else {
          // Image too too big
          await tgbot.sendTextMessage(
            '（图片无法上传）\n$rankingDate #No${i + 1}\n\n> ${obj.name}\n> #${obj.author}\n> ${obj.illustId}\nhttps://www.pixiv.net/artworks/${obj.illustId}',
          );
          break;
        }
      }
    }

    sleep(uploadDelay);
  }

  log('Done.');

  /// download -> upload [X]
  //
  // for (var obj in objList) {
  //   await obj.getPagesUri(d);

  //   // downloadImages
  //   final pathList = await downloadImages(
  //     obj.pageUriList,
  //     obj.illustId.toString(),
  //   );

  //   await tgbot.sendLocalPhotos(
  //     pathList,
  //     caption: '${obj.name}-${obj.author}-${obj.illustId}',
  //   );
  //   sleep(uploadDelay);
  // }
}
