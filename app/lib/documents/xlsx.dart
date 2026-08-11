import 'dart:typed_data';

import 'ooxml.dart';

/// A real spreadsheet, from CSV.
///
/// Same split as the Word writer: the model supplies CSV — a format it writes
/// well and a person can read in the transcript — and the app builds the
/// container.
///
/// **Numbers are written as numbers.** A sheet whose figures are text looks
/// identical until somebody sums a column and gets zero, and that is the whole
/// reason to want a spreadsheet rather than a table in a document.
Uint8List buildXlsx(String csv, {String sheetName = 'Sheet1', String? title}) {
  final rows = parseCsv(csv);
  final header = _hasHeader(rows);

  final package = OoxmlPackage()
    ..addXml('[Content_Types].xml', _contentTypes)
    ..addXml(
        '_rels/.rels',
        rootRels(
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
          'xl/workbook.xml',
        ))
    ..addXml('xl/_rels/workbook.xml.rels', _workbookRels)
    ..addXml('xl/workbook.xml', _workbook(sheetName))
    ..addXml('xl/styles.xml', _styles)
    ..addXml('docProps/core.xml', _core(title ?? sheetName))
    ..addXml('xl/worksheets/sheet1.xml', _sheet(rows, header: header));

  return package.encode();
}

/// Whether row one reads as column names.
///
/// True when there is more than one row and nothing in the first row is a
/// number. A sheet of readings whose first row is `2026,14,2.1` has no header,
/// and bolding it would be the app asserting something about the data that is
/// not true.
bool _hasHeader(List<List<String>> rows) =>
    rows.length > 1 && rows.first.isNotEmpty && rows.first.every((c) => _numberOf(c) == null);

/// The value as a number, or null when it is text.
///
/// Deliberately strict: no thousands separators, no currency symbols, no
/// percentages. `$1,200` parsed as 1200 would silently drop the currency, and
/// a column that is sometimes text and sometimes a number is worse than one
/// that is consistently text.
num? _numberOf(String cell) {
  final trimmed = cell.trim();
  if (trimmed.isEmpty) return null;
  return num.tryParse(trimmed);
}

/// Splits CSV into rows of fields.
///
/// Handles quoted fields containing commas, newlines and doubled quotes,
/// because a model asked for a table of comments will produce all three and a
/// `split(',')` would shred it. Exported so it can be tested on its own — it is
/// the part most likely to be wrong.
List<List<String>> parseCsv(String csv) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var any = false;

  void endField() {
    row.add(field.toString());
    field.clear();
    any = true;
  }

  void endRow() {
    endField();
    // A trailing newline is not an empty final row.
    if (row.length == 1 && row.first.isEmpty) {
      row = <String>[];
      any = false;
      return;
    }
    rows.add(row);
    row = <String>[];
    any = false;
  }

  final text = csv.replaceAll('\r\n', '\n');
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 1;
        } else {
          quoted = false;
        }
      } else {
        field.write(char);
      }
      continue;
    }
    switch (char) {
      case '"':
        quoted = true;
      case ',':
        endField();
      case '\n':
        endRow();
      default:
        field.write(char);
    }
  }
  if (field.isNotEmpty || any || row.isNotEmpty) endRow();
  return rows;
}

/// `A1`, `B7`, `AA3` — the reference a cell must carry.
String cellRef(int column, int row) {
  var name = '';
  var n = column;
  while (n >= 0) {
    name = String.fromCharCode(65 + (n % 26)) + name;
    n = (n ~/ 26) - 1;
  }
  return '$name${row + 1}';
}

String _sheet(List<List<String>> rows, {required bool header}) {
  final body = StringBuffer();
  for (var r = 0; r < rows.length; r++) {
    body.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final value = rows[r][c];
      final number = _numberOf(value);
      final style = header && r == 0 ? ' s="1"' : '';
      if (number != null) {
        body.write('<c r="${cellRef(c, r)}"$style><v>$number</v></c>');
      } else if (value.isNotEmpty) {
        // Inline strings rather than a shared-strings table. One fewer part,
        // one fewer index to get wrong, and the size difference only matters
        // on a sheet far larger than anything written here.
        body.write('<c r="${cellRef(c, r)}"$style t="inlineStr">'
            '<is><t xml:space="preserve">${xmlEscape(value)}</t></is></c>');
      }
    }
    body.write('</row>');
  }

  final widths = _columnWidths(rows);

  return '$xmlHeader'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      // The header stays put while you scroll. On a sheet of any length that
      // is the difference between reading a column and counting across.
      '${header ? '<sheetViews><sheetView workbookViewId="0">'
          '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
          '</sheetView></sheetViews>' : ''}'
      '$widths'
      '<sheetData>$body</sheetData>'
      '</worksheet>';
}

/// Columns wide enough to read.
///
/// The default width truncates almost every real label, and a sheet that opens
/// showing `####` is one somebody has to fix before they can look at it.
/// Capped, because one long free-text cell should not make a column fill the
/// screen.
String _columnWidths(List<List<String>> rows) {
  final widest = <int, int>{};
  for (final row in rows) {
    for (var c = 0; c < row.length; c++) {
      final length = row[c].length;
      if (length > (widest[c] ?? 0)) widest[c] = length;
    }
  }
  if (widest.isEmpty) return '';

  final columns = widest.entries.map((e) {
    final width = (e.value + 2).clamp(8, 60);
    return '<col min="${e.key + 1}" max="${e.key + 1}" width="$width" customWidth="1"/>';
  }).join();
  return '<cols>$columns</cols>';
}

const _contentTypes = '$xmlHeader'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    '</Types>';

const _workbookRels = '$xmlHeader'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';

String _workbook(String sheetName) => '$xmlHeader'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<sheets><sheet name="${xmlEscape(_safeSheetName(sheetName))}" sheetId="1" r:id="rId1"/></sheets>'
    '</workbook>';

/// A sheet name Excel will accept.
///
/// Thirty-one characters, and none of `[]:*?/\`. Excel does not report an
/// invalid name — it reports the workbook as unreadable, so this is a
/// correctness rule rather than tidiness.
String _safeSheetName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  if (cleaned.isEmpty) return 'Sheet1';
  return cleaned.length <= 31 ? cleaned : cleaned.substring(0, 31);
}

String _core(String title) => '$xmlHeader'
    '<cp:coreProperties '
    'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:title>${xmlEscape(title)}</dc:title>'
    '</cp:coreProperties>';

/// Two formats: the default, and a bold one for the header row.
///
/// The order of these lists is the index space `s="1"` points into, so nothing
/// here is decorative — moving an entry silently restyles the sheet.
const _styles = '$xmlHeader'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<fonts count="2">'
    '<font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font>'
    '</fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border/></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="2">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '</cellXfs>'
    // openpyxl warns without this and applies its own default. Excel tolerates
    // the omission; a reader that has to guess is a reader that can guess
    // differently, so it is stated.
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';
