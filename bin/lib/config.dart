import 'dart:io';

/// Centralized application configuration.
///
/// All sensitive values are loaded from `in/*.key` files that are excluded
/// from version control via `.gitignore`.
abstract class Config {
  // Pixiv
  static final cookie = File('in/phpsessid.key').readAsStringSync().trim();

  // Telegram
  static final botToken = File('in/botToken.key').readAsStringSync().trim();
  static final chatId = File('in/chatID.key').readAsStringSync().trim();
  // static final chatId = File('in/chatID-test.key').readAsStringSync().trim();

  static final chatUrl = File('in/chatUrl.key').readAsStringSync().trim();

  // Telegraph
  static final telegraphToken = File(
    'in/telegraphToken.key',
  ).readAsStringSync().trim();

  // Cloudflare proxy for Pixiv images
  static final proxy = File('in/imgProxy.key').readAsStringSync().trim();

  // Bark push notifications
  static final barkSuccessUrl = File(
    'in/bark-success.key',
  ).readAsStringSync().trim();
  static final barkFailUrl = File('in/bark-fail.key').readAsStringSync().trim();
}
