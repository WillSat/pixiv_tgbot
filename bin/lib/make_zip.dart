import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';

import 'fetch_ranking.dart';
import '../utils.dart';

Future<String> makeRankingZip(Dio dio, List<RankingElement> list) async {
  final dt = DateTime.now();
  final year = dt.year.toString();
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');

  final zipPath =
      '${Directory.current.path}/PixivRanking_$year-$month-$day.zip';
  final zipFile = File(zipPath);

  // 使用流式写入
  final output = zipFile.openWrite();
  final encoder = ZipFileEncoder();
  encoder.open(zipPath);

  try {
    // 下载并逐个添加到ZIP，不保留在内存中
    for (var i = 0; i < list.length; i++) {
      final ranking = 'NO${i + 1}-${list[i].illustId}';

      for (var j = 0; j < list[i].originalPageUriList.length; j++) {
        final uri = list[i].originalPageUriList[j];

        try {
          final response = await downDio.get<List<int>>(
            uri,
            options: Options(
              responseType: ResponseType.bytes,
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:143.0) Gecko/20100101 Firefox/143.0',
                'Accept':
                    'image/avif,image/webp,image/png,image/svg+xml,image/*;q=0.8,*/*;q=0.5',
                'Accept-Language': 'zh-CN,zh;q=0.7,en-US;q=0.3',
                'Referer': 'https://www.pixiv.net/',
              },
            ),
          );

          final name = '$ranking-${j + 1}.' + getExt(response.data!);

          encoder.addArchiveFile(
            ArchiveFile(name, response.data!.length, response.data!),
          );

          // 强制垃圾回收（可选）
          if (i % 10 == 0) {
            await Future.delayed(Duration.zero);
          }
        } catch (e) {
          wrn('Failed to download $uri: $e');
        }
      }
    }
  } finally {
    encoder.close();
    await output.close();
  }

  log('ZIP file generated!');
  return zipFile.path;
}
