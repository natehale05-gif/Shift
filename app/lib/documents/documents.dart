import 'dart:typed_data';

import 'docx.dart';
import 'pptx.dart';
import 'xlsx.dart';

/// One entry point: a path and some text in, a real document out.
///
/// The extension decides. That is the only rule, and it is the one the person
/// reading the transcript can check — `report.docx` says what it is, where a
/// `format: "word"` argument beside a `.xlsx` path would be a disagreement
/// nobody notices until the file will not open.
///
/// Returns null for anything else, so the caller can say what it does support
/// rather than writing a `.pdf` full of WordprocessingML.
Uint8List? buildDocument(String path, String content) =>
    switch (extensionOf(path)) {
      'docx' => buildDocx(content),
      'xlsx' => buildXlsx(content, sheetName: _sheetNameOf(path)),
      'pptx' => buildPptx(content),
      _ => null,
    };

/// The formats this can write, for a message that names them.
const List<String> kDocumentExtensions = ['docx', 'xlsx', 'pptx'];

/// The lower-cased extension, without the dot. Empty when there is none.
String extensionOf(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// A sheet named after the file, which is what a person expects to see on the
/// tab — `Sheet1` on a workbook called `regions.xlsx` reads as untouched
/// default.
String _sheetNameOf(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  final stem = dot <= 0 ? name : name.substring(0, dot);
  if (stem.isEmpty) return 'Sheet1';
  return stem[0].toUpperCase() + stem.substring(1);
}
