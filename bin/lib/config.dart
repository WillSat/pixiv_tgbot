import 'dart:io';

/// Centralized application configuration.
///
/// All sensitive values are loaded from `in/*.key` files that are excluded
/// from version control via `.gitignore`.
abstract class Config {
  static String _readKey(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('ERROR: Missing required config file: $path');
      exit(1);
    }
    return file.readAsStringSync().trim();
  }

  // Pixiv
  static final cookie = _readKey('in/phpsessid.key');

  // Telegram
  static final botToken = _readKey('in/botToken.key');
  static final chatId = _readKey('in/chatID.key');
  // static final chatId = _readKey('in/chatID-test.key');

  static final chatUrl = _readKey('in/chatUrl.key');

  // Telegraph
  static final telegraphToken = _readKey('in/telegraphToken.key');

  // Cloudflare proxy for Pixiv images
  static final proxy = _readKey('in/imgProxy.key');

  // Bark push notifications
  static final barkSuccessUrl = _readKey('in/bark-success.key');
  static final barkFailUrl = _readKey('in/bark-fail.key');
}
