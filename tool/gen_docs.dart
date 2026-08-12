// Writes one of each document to a directory, for opening with a reader that
// is not this one. Not a test: the readers live outside Dart.
import 'dart:io';

import 'package:shift/documents/docx.dart';
import 'package:shift/documents/pptx.dart';
import 'package:shift/documents/xlsx.dart';

const _markdown = '''
# Q3 Brief

Revenue was **up 14%** and churn was *flat*. The Berlin office opened in
August, which is the quarter's one structural change.

## What moved

- Revenue, up 14% year on year
- Churn, flat at 2.1%
- Headcount, up by nine

## What to do next

1. Confirm the Berlin numbers with finance
2. Rewrite the retention section
3. Send it to the board on Friday

> The numbers are provisional until finance signs them off.

Run `make report` to regenerate this.

```
make report --quarter 3
make publish
```

Dave's notes say <3 & "more" — punctuation that has to survive.
''';

const _csv = '''
Region,Revenue,Churn,Notes
Berlin,124000,2.1,"Opened in August, ramping"
London,981250,1.8,"Steady; renewals due Q4"
Lisbon,44000,3.4,"One large account said ""maybe"""
Total,1149250,2.4,
''';

const _deck = '''
# Q3 in three minutes

Where the quarter landed, and what it changed.

## What moved

- Revenue up 14% year on year
- Churn flat at 2.1%
- Berlin opened in August

## What we are doing about it

1. Confirm the numbers with finance
2. Rewrite retention
3. Take it to the board

---

# Questions?

Ask Dave — he has the "detail" & the caveats.
''';

void main(List<String> args) {
  final dir = Directory(args.isEmpty ? 'build/documents' : args.first)
    ..createSync(recursive: true);
  File('${dir.path}/brief.docx').writeAsBytesSync(buildDocx(_markdown));
  File('${dir.path}/regions.xlsx')
      .writeAsBytesSync(buildXlsx(_csv, sheetName: 'Regions'));
  File('${dir.path}/deck.pptx').writeAsBytesSync(buildPptx(_deck));
  stdout.writeln('wrote ${dir.path}');
}
