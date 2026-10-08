/// Source ranges let visual edits replace only the edited block. Unedited
/// whitespace, unsupported syntax and line endings remain byte-for-byte intact.
class PlanMarkdownBlock {
  const PlanMarkdownBlock(this.start, this.end, this.source);
  final int start;
  final int end;
  final String source;

  static final _prefix = RegExp(
    r'^( {0,3}(?:#{1,6} |(?:[-+*]|\d+[.)]) (?:\[[ xX]\] )?|> ))',
  );
  String get prefix =>
      source.contains('\n') ? '' : _prefix.firstMatch(source)?[1] ?? '';
  String get body => source.substring(prefix.length);
  bool get isTask => RegExp(r'^ {0,3}[-+*] \[[ xX]\] ').hasMatch(prefix);
  bool get checked => RegExp(r'^ {0,3}[-+*] \[[xX]\] ').hasMatch(source);
}

List<PlanMarkdownBlock> parsePlanMarkdown(String source, {int offset = 0}) {
  final lines = RegExp(
    r'[^\n]*(?:\n|$)',
  ).allMatches(source).where((m) => m.start < source.length).toList();
  final blocks = <PlanMarkdownBlock>[];
  var index = 0;
  String line(int i) => lines[i][0]!.replaceFirst(RegExp(r'\r?\n$'), '');
  bool boundary(String value) => RegExp(
    r'^\s*(?:#{1,6}\s|[-+*]\s|\d+[.)]\s|>|`{3,}|~{3,}|\|)',
  ).hasMatch(value);
  while (index < lines.length) {
    if (line(index).trim().isEmpty) {
      index++;
      continue;
    }
    final start = index;
    final first = line(index);
    final fence = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(first)?[1];
    index++;
    if (fence != null) {
      while (index < lines.length) {
        final closing = line(index++).trim();
        if (RegExp(
          '^${RegExp.escape(fence[0])}{${fence.length},}\\s*\$',
        ).hasMatch(closing)) {
          break;
        }
      }
    } else if (first.trimLeft().startsWith('|')) {
      while (index < lines.length && line(index).trimLeft().startsWith('|')) {
        index++;
      }
    } else if (!boundary(first)) {
      while (index < lines.length &&
          line(index).trim().isNotEmpty &&
          !boundary(line(index))) {
        index++;
      }
    }
    final begin = lines[start].start;
    final last = lines[index - 1];
    final end = last.start + line(index - 1).length;
    blocks.add(
      PlanMarkdownBlock(
        offset + begin,
        offset + end,
        source.substring(begin, end),
      ),
    );
  }
  return blocks;
}
