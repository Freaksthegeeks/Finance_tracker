import 'dart:convert';
import 'dart:io';

// Copy only the public endpoint. Never bundle the root .env or database secrets.
void main() {
  final mobile = File.fromUri(Platform.script).parent.parent;
  final env = File('${mobile.parent.path}/.env');
  if (!env.existsSync()) {
    stderr.writeln(
      'Missing root .env. Set PUBLIC_URL before configuring mobile.',
    );
    exitCode = 1;
    return;
  }
  String? value;
  for (final line in env.readAsLinesSync()) {
    final match = RegExp(r'^\s*(?:export\s+)?PUBLIC_URL\s*=\s*(.*?)\s*$')
        .firstMatch(line);
    if (match == null) continue;
    value = match.group(1)!;
    if (value.startsWith('"') || value.startsWith("'")) {
      final quote = value[0];
      final end = value.indexOf(quote, 1);
      if (end > 0) value = value.substring(1, end);
    } else {
      value = value.split(RegExp(r'\s+#')).first.trim();
    }
  }
  final uri = Uri.tryParse(value ?? '');
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    stderr.writeln(
      'PUBLIC_URL must be an HTTP(S) backend URL without credentials, query or fragment.',
    );
    exitCode = 1;
    return;
  }
  final output = File('${mobile.path}/assets/public_config.json');
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'PUBLIC_URL': value})}\n',
  );
  stdout.writeln(
    'Mobile endpoint configured from root .env (PUBLIC_URL only).',
  );
}
