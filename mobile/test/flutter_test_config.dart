import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Use the SDK's Material fonts so mobile layout tests measure real glyphs.
Future<void> testExecutable(Future<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final configFile = File('.dart_tool/package_config.json');
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  final flutterPackage = (config['packages'] as List).firstWhere(
    (p) => p['name'] == 'flutter',
  );
  final flutterRoot = configFile.absolute.uri.resolve(
    '${flutterPackage['rootUri']}/',
  );
  final fonts = flutterRoot.resolve(
    '../../bin/cache/artifacts/material_fonts/',
  );
  final textLoader = FontLoader('TrackerSans');
  for (final file in ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']) {
    textLoader.addFont(
      Future.value(
        ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync()),
      ),
    );
  }
  await textLoader.load();
  for (final (family, file) in [
    ('MaterialIcons', 'materialicons-regular.otf'),
  ]) {
    final loader = FontLoader(family);
    loader.addFont(
      Future.value(
        ByteData.sublistView(
          File.fromUri(fonts.resolve(file)).readAsBytesSync(),
        ),
      ),
    );
    await loader.load();
  }
  await testMain();
}
