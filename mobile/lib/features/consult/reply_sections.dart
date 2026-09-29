import '../../core/content/safety_content.dart';

/// One `### ` section of a reply.
class ReplySection {
  const ReplySection({required this.number, required this.title, required this.body, required this.provisional});

  /// "3" for "### 3. …", null for unnumbered headings.
  final String? number;

  /// Heading without its number or "PROVISIONAL — … ·" prefix.
  final String title;

  /// Markdown under the heading.
  final String body;

  /// The inspector requires "PROVISIONAL" on every heading from section 3
  /// onward when the confidence ceiling is Low.
  final bool provisional;

  String get heading => number == null ? title : '$number. $title';
}

class ParsedReply {
  const ParsedReply({required this.intro, required this.sections, required this.hasDisclaimer});

  /// Markdown before the first heading (usually empty).
  final String intro;
  final List<ReplySection> sections;

  /// True when the verbatim disclaimer was found (and removed, so the app can
  /// always show it in a fixed place instead of inside a collapsed section).
  final bool hasDisclaimer;
}

final _heading = RegExp(r'^###\s+(.*)$', multiLine: true);
final _numbered = RegExp(r'^(\d+[a-z]?)\.\s+(.*)$');
final _provisionalPrefix = RegExp(r'^PROVISIONAL\b[^·]*·\s*', caseSensitive: false);

/// Splits a reply's markdown into its numbered sections.
ParsedReply parseReply(String markdown) {
  var text = markdown;
  var hasDisclaimer = false;
  final disclaimerLine = RegExp('^>\\s*\\**${RegExp.escape(kDisclaimer)}\\**\\s*\$', multiLine: true);
  if (disclaimerLine.hasMatch(text)) {
    text = text.replaceAll(disclaimerLine, '');
    hasDisclaimer = true;
  } else if (text.contains(kDisclaimer)) {
    hasDisclaimer = true;
  }

  final matches = _heading.allMatches(text).toList();
  final intro = (matches.isEmpty ? text : text.substring(0, matches.first.start)).trim();
  final sections = <ReplySection>[];
  for (final (i, m) in matches.indexed) {
    final end = i + 1 < matches.length ? matches[i + 1].start : text.length;
    var heading = m.group(1)!.trim();
    String? number;
    final n = _numbered.firstMatch(heading);
    if (n != null) {
      number = n.group(1);
      heading = n.group(2)!;
    }
    final provisional = heading.toUpperCase().startsWith('PROVISIONAL');
    sections.add(
      ReplySection(
        number: number,
        title: heading.replaceFirst(_provisionalPrefix, ''),
        body: text.substring(m.end, end).trim(),
        provisional: provisional,
      ),
    );
  }
  return ParsedReply(intro: intro, sections: sections, hasDisclaimer: hasDisclaimer);
}
