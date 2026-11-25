import 'dart:convert';

import 'package:flutter/services.dart';

class AppConfig {
  final Uri apiBase;
  final String userId;
  AppConfig(
    String publicUrl, {
    this.userId = const String.fromEnvironment(
      'TRACKER_USER_ID',
      defaultValue: 'google_varun_123',
    ),
  }) : apiBase = normalizeApiBase(publicUrl);

  static Uri normalizeApiBase(String value) {
    final uri = Uri.parse(value.trim());
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'PUBLIC_URL must be a valid HTTP(S) backend URL.',
      );
    }
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    return uri.replace(path: path.endsWith('/api') ? '$path/' : '$path/api/');
  }

  static Future<AppConfig> load() async {
    final json = jsonDecode(
      await rootBundle.loadString('assets/public_config.json'),
    ) as Map<String, dynamic>;
    return AppConfig(json['PUBLIC_URL'] as String);
  }
}
