@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/providers/streaming/sse_client.dart';

void main() {
  test('a browser build gets the fetch transport, not the buffering one', () {
    // The failure this guards against raises nothing. `package:http`'s default
    // client works in a browser — it is just XHR-backed, so it hands over the
    // whole body at the end instead of streaming it. A reply would still
    // arrive, complete and correct, in one lump; the only symptom is that the
    // app looks like it has a slow model.
    //
    // v1 keyed this pair on `dart.library.html`, which is false under
    // dart2wasm — the compiler v2 uses. Ported unchanged, every web build
    // would have quietly taken the wrong arm.
    //
    // **What this test does not cover.** `--platform chrome` compiles with
    // dart2js, where `dart.library.html` is *also* true — so this would pass
    // just as happily with v1's condition. What it proves is that the web arm
    // compiles (fetch_client under a web target was the wave's one unverified
    // dependency) and that the assertion itself works, checked by pointing the
    // condition at `dart.library.io` and watching it go red. The wasm arm is
    // confirmed separately, against a real `--wasm` build, once something the
    // app actually runs imports this.
    expect(SseClient.clientKind, 'fetch');
  });
}
