/// The two things every OOXML format needs: escaped text, and a ZIP.
///
/// A `.docx`, `.xlsx` and `.pptx` are the same container with different parts
/// inside, so the container lives here once. What is *not* shared is the parts:
/// they differ in every element, and a common "document builder" over three
/// unrelated schemas would be an abstraction over a coincidence.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// XML-escapes [value] for a text node or an attribute.
///
/// Apostrophes are escaped too. Word does not require it, but a title with an
/// apostrophe inside a double-quoted attribute is the kind of thing that works
/// in every test and breaks on the one real document somebody names
/// `Dave's notes`.
String xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Strips what XML 1.0 cannot carry at all.
///
/// A model can emit a control character — a stray `` out of a bad paste —
/// and Word does not report a bad character, it reports the file as corrupt.
/// Tab, newline and carriage return are kept because they are legal and mean
/// something.
String xmlSafe(String value) => value.replaceAll(
    RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

/// Builds the package.
///
/// Parts are added in the order given, which is the order they appear in the
/// archive. Not required by the format — a reader goes through
/// `[Content_Types].xml` — but it makes an `unzip -l` of a broken file
/// readable, and that is how these get debugged.
class OoxmlPackage {
  final Archive _archive = Archive();

  void addXml(String path, String xml) {
    final bytes = utf8.encode(xmlSafe(xml));
    _archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  Uint8List encode() => Uint8List.fromList(ZipEncoder().encode(_archive));
}

/// The declaration every part starts with.
const String xmlHeader =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

/// The package-level relationships: the main part, and the core properties.
///
/// Identical in all three formats apart from the main type and target, which
/// is why it is a function rather than three near-copies.
///
/// **The core-properties relationship is not optional.** A `docProps/core.xml`
/// that nothing points at is a file in the ZIP that no reader ever opens: the
/// title falls back to a default and nothing complains. That is exactly how the
/// first draft of this shipped — the part was written, the part was correct,
/// and the document was called "Word Document" until a reader that was not
/// mine was pointed at it.
String rootRels(String type, String target) => '$xmlHeader'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="$type" Target="$target"/>'
    '<Relationship Id="rId2" '
    'Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" '
    'Target="docProps/core.xml"/>'
    '</Relationships>';
