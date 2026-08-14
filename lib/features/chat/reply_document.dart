import 'dart:typed_data';

import '../../documents/docx.dart';
import '../../turn/request_title.dart';

/// A reply, as a file somebody can keep.
///
/// The point of the Work mode writers is not Work mode. An answer worth
/// keeping is far more often one you asked for in Chat — a summary, a draft, a
/// plan — and until now the only way out of the transcript was Copy, which
/// gets you asterisks and backticks in a Word document.
///
/// Pure, and separate from the button, so what the file is called and what is
/// in it can be asserted without a save dialog. `saveFile` off-web opens one,
/// and a test that has to answer a dialog tests the dialog.
typedef ReplyDocument = ({String name, Uint8List bytes});

/// Names the file from what was **asked**, not from the answer.
///
/// A reply's own first line is often "Sure — here's a summary of the Q3
/// notes:", which makes a terrible filename; the question is the thing the
/// person will look for it under. This is the same rule that names an
/// artifact, and it is the same rule for the same reason: v1 had two and one
/// of them was bad.
ReplyDocument documentForReply({required String prompt, required String markdown}) {
  final title = titleFromRequest(prompt, fallback: 'Answer');
  return (
    name: '${fileStem(title, fallback: 'answer')}.docx',
    bytes: buildDocx(markdown, title: title),
  );
}
