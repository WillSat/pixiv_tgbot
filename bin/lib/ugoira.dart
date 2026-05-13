import 'dart:io';
import 'package:dio/dio.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import '../utils.dart';
import 'config.dart';
import 'pixiv_api.dart';

final _downloadDio = Dio();

const _crf = 18;

/// Download a Pixiv ugoira ZIP, extract frames, and convert to MP4 (H.265).
///
/// Returns the path to the MP4 file, or null on failure.
Future<String?> downloadUgoiraAsMp4(int illustId) async {
  // 1. Get metadata
  final meta = await getUgoiraMeta(illustId);
  if (meta == null) return null;

  final (zipUrl: zipUrl, frames: frames) = meta;
  LOG('Downloading ugoira $illustId: $zipUrl');

  // 2. Set up temp directory
  final tmpDir = Directory('${Directory.current.path}/temp_$illustId')
    ..createSync(recursive: true);

  try {
    final zipPath = p.join(tmpDir.path, '$illustId.zip');
    await _downloadDio.download(Config.proxy + zipUrl, zipPath);

    // 3. Extract zip
    final extractDir = Directory(p.join(tmpDir.path, 'frames'))
      ..createSync(recursive: true);

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

    // 4. Generate concat file for ffmpeg
    final concatFile = File(p.join(tmpDir.path, 'concat.txt'));
    final sb = StringBuffer();
    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i];
      sb.writeln(
        "file '${p.join(extractDir.path, frame.file).replaceAll('\\', '/')}'",
      );
      if (i < frames.length - 1) {
        sb.writeln('duration ${frame.delay / 1000.0}');
      }
    }
    // Repeat the last frame so it has a visible duration
    final lastFrame = frames.last;
    sb.writeln(
      "file '${p.join(extractDir.path, lastFrame.file).replaceAll('\\', '/')}'",
    );
    concatFile.writeAsStringSync(sb.toString());

    // 5. Run ffmpeg: concat frames → H.265 MP4
    final outputPath = '${tmpDir.path}/$illustId-$_crf.mp4';
    final result = await Process.run('ffmpeg', [
      '-y',
      '-f', 'concat',
      '-safe', '0',
      '-i', concatFile.path,
      '-vsync', 'vfr',
      '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2', // ensure even dimensions
      '-c:v', 'libx265',
      '-preset', 'fast',
      '-crf', _crf.toString(),
      '-pix_fmt', 'yuv420p',
      outputPath,
    ]);

    if (result.exitCode == 0) {
      LOG('MP4 file created: $outputPath');
      return outputPath;
    } else {
      WRN('ffmpeg error:\n${result.stderr}');
      return null;
    }
  } catch (e) {
    WRN('Error in downloadUgoiraAsMp4: $e');
    return null;
  }
}
