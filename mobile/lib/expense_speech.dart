String normalizeVoiceTranscript(String transcript) => transcript
    .trim()
    .replaceFirst(RegExp(r'[.!?]+$'), '')
    .replaceAllMapped(RegExp(r'(?<=\d),(?=\d)'), (_) => '')
    .replaceAllMapped(
      RegExp(r'₹\s*(\d+(?:\.\d{1,2})?)'),
      (match) => '${match[1]} rupees',
    );

/// Parses the supported command shape `<amount> rupees [for] <note>`.
({String? amount, String note}) parseExpenseSpeech(String transcript) {
  final text = normalizeVoiceTranscript(transcript);
  final match = RegExp(
    r'^(?:(?:i spent|spent|add|paid)\s+)?(.+?)\s+rupees?(?=$|\s|[,.])\s*[,.:]?\s*(?:for\s+)?(.*)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return (amount: null, note: text);

  final spoken = match.group(1)!.toLowerCase();
  final amount = RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(spoken)
      ? spoken
      : spokenNumber(spoken);
  return amount == null
      ? (amount: null, note: text)
      : (amount: amount, note: match.group(2)!.trim());
}

const _units = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];
const _tens = [
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
];

String? spokenNumber(String phrase) {
  phrase = phrase.trim().toLowerCase();
  if (RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(phrase)) return phrase;
  final parts = phrase.replaceAll('-', ' ').split(RegExp(r'\s+point\s+'));
  if (parts.length > 2) return null;
  final whole = _wholeNumber(parts.first);
  if (whole == null) return null;
  if (parts.length == 1) return '$whole';

  final digits = parts.last.split(RegExp(r'\s+'));
  if (digits.length > 2) return null;
  final values = digits.map(_units.indexOf).toList();
  if (values.any((value) => value < 0 || value > 9)) return null;
  return '$whole.${values.join()}';
}

int? _wholeNumber(String words) {
  const scales = {'crore': 10000000, 'lakh': 100000, 'thousand': 1000};
  var total = 0;
  var previousScale = 1000000000;
  final group = <String>[];
  for (final word in words.split(RegExp(r'\s+'))) {
    final scale = scales[word];
    if (scale == null) {
      group.add(word);
      continue;
    }
    final value = _underThousand(group);
    if (value == null || value == 0 || scale >= previousScale) return null;
    total += value * scale;
    previousScale = scale;
    group.clear();
  }
  if (total > 0 && group.firstOrNull == 'and') group.removeAt(0);
  if (group.isEmpty) return total > 0 ? total : null;
  final remainder = _underThousand(group);
  return remainder == null ? null : total + remainder;
}

int? _underThousand(List<String> words) {
  var hundreds = 0;
  var rest = words;
  if (words.length >= 2 && words[1] == 'hundred') {
    final digit = _units.indexOf(words.first);
    if (digit < 1 || digit > 9) return null;
    hundreds = digit * 100;
    rest = words.sublist(2);
    if (rest.isEmpty) return hundreds;
    if (rest.first == 'and') rest = rest.sublist(1);
  }
  if (rest.isEmpty || rest.length > 2) return null;
  final unit = _units.indexOf(rest.first);
  if (rest.length == 1 && unit >= 0) return hundreds + unit;
  final ten = _tens.indexOf(rest.first);
  if (ten < 2) return null;
  if (rest.length == 1) return hundreds + ten * 10;
  final last = _units.indexOf(rest.last);
  return last > 0 && last < 10 ? hundreds + ten * 10 + last : null;
}
