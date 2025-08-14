import 'dart:io';
import 'package:dio/dio.dart';
import '../utils.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';

final proxy = File('in/imgProxy.key').readAsStringSync();
final cookie = File('in/phpsessid.key').readAsStringSync();

final dio = Dio(
  BaseOptions(
    headers: {
      'Referer': 'https://www.pixiv.net',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:143.0) Gecko/20100101 Firefox/143.0',
      'Cookie': cookie,
    },
  ),
);

Future<String?> downloadUgoiraAsMp4(String pid) async {
  try {
    // 1. 获取动图元数据
    final metaUrl = 'https://www.pixiv.net/ajax/illust/$pid/ugoira_meta';
    final metaResp = await dio.get(metaUrl);
    final meta = metaResp.data;

    if (meta['error'] == true) {
      wrn('Failed to get PIXIV metadata: ${meta['message']}');
      return null;
    }

    final body = meta['body'];
    final zipUrl = body['originalSrc'] as String;
    final frames = (body['frames'] as List)
        .map((f) => FrameInfo(file: f['file'], delay: f['delay']))
        .toList();

    log('Downloading: $zipUrl');

    // 2. 下载 zip
    final tmpDir = Directory('${Directory.current.path}/temp_$pid');
    tmpDir.createSync(recursive: true);
    final zipPath = p.join(tmpDir.path, '$pid.zip');
    await dio.download(proxy + zipUrl, zipPath);

    // 3. 解压 zip
    final extractDir = Directory(p.join(tmpDir.path, 'frames'));
    extractDir.createSync(recursive: true);

    final inputStream = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeStream(inputStream);
    inputStream.close();

    for (final file in archive) {
      if (file.isFile) {
        final filePath = p.join(extractDir.path, file.name);
        File(filePath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(file.content as List<int>);
      }
    }

    // 4. 生成 concat 列表文件（ffmpeg 合成用）
    final concatFile = File(p.join(tmpDir.path, 'concat.txt'));
    final sb = StringBuffer();
    for (final frame in frames) {
      // delay ms → s
      final delaySec = frame.delay / 1000.0;
      sb.writeln(
        "file '${p.join(extractDir.path, frame.file).replaceAll("\\", "/")}'",
      );
      sb.writeln('duration $delaySec');
    }
    concatFile.writeAsStringSync(sb.toString());

    // 5. 调用 ffmpeg 合成 mp4
    final outputPath = '${tmpDir.path}/$pid.mp4';
    final ffmpegArgs = [
      '-y',
      '-f', 'concat',
      '-safe', '0',
      '-i', concatFile.path,
      '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2', // 保证偶数宽高
      '-c:v', 'libx265', // hevc 编码器
      '-pix_fmt', 'yuv420p',
      outputPath,
    ];
    final result = await Process.run('ffmpeg', ffmpegArgs);

    if (result.exitCode == 0) {
      log('MP4 file successfully created: $outputPath');
      return '${tmpDir.path}/$pid.mp4';
    } else {
      wrn('Something wrong with ffmpeg:\n${result.stderr}');
      return null;
    }
  } catch (e) {
    wrn('Error in downloadUgoiraAsMp4: $e');
    return null;
  }
}

class FrameInfo {
  final String file;
  final int delay;
  FrameInfo({required this.file, required this.delay});
}
