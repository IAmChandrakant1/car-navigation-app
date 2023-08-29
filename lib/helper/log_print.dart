logPrint(var s, {String? msg}) {
  bool isLog = true;
  if (msg != null) {
    msg = '\x1B[32m ${msg}\x1B[0m';
  } else {
    msg = '';
  }
  s = '\x1B[34m$s\x1B[0m';
  if (isLog) {
    printLongString('$msg--->>> $s');
  }
}

/// Print Long String
void printLongString(String text) {
  final pattern = new RegExp('.{1,800}');
  pattern.allMatches(text).forEach((match) => print(match.group(0)));
}
