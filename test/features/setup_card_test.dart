import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/backend/no_backend.dart';
import 'package:shift/backend/shift_backend.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/account_store.dart';
import 'package:shift/features/settings/server_card.dart';
import 'package:shift/features/settings/setup_card.dart';

/// The card the Server card's own sentence points at.
///
/// **It did not exist, and the sentence said "below".** `setupLinks()` was
/// written with four links, each carrying a deep URL and the value to paste,
/// exposed on the store — and rendered by nothing. So the app named the exact
/// blocker it was stuck on and then showed no way to clear it.
void main() {
  Widget host(ShiftBackend backend, {bool withServerCard = false}) {
    final store = AccountStore(backend: backend)..restore();
    return ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                if (withServerCard) const ServerCard(),
                const SetupCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  group('who sees it', () {
    testWidgets('nobody, when the build has no server', (t) async {
      // `NoBackend.setupLinks()` is empty, so there is nothing to show and no
      // dashboard to send anyone to.
      await t.pumpWidget(host(NoBackend()));
      await t.pumpAndSettle();
      expect(find.text('Server settings'), findsNothing);
    });

    testWidgets('not a signed-out visitor', (t) async {
      await t.pumpWidget(host(_Host()));
      await t.pumpAndSettle();
      expect(find.text('Server settings'), findsNothing);
    });

    testWidgets('a signed-in account does', (t) async {
      await t.pumpWidget(host(_Host(signedIn: true)));
      await t.pumpAndSettle();
      expect(find.text('Server settings'), findsOneWidget);
    });
  });

  testWidgets('every link gets a row', (t) async {
    final backend = _Host(signedIn: true);
    await t.pumpWidget(host(backend));
    await t.pumpAndSettle();

    for (final link in backend.setupLinks()) {
      expect(find.text(link.title), findsOneWidget, reason: link.title);
      expect(find.widgetWithText(TextButton, link.action), findsWidgets,
          reason: link.action);
    }
  });

  testWidgets('laid out under the Server card, it is under it', (t) async {
    await t.pumpWidget(host(_Host(signedIn: true), withServerCard: true));
    await t.pumpAndSettle();

    expect(t.getTopLeft(find.text('Server settings')).dy,
        greaterThan(t.getTopLeft(find.text('Server')).dy));
  });

  test('and Settings is what puts it there', () {
    // **The test above cannot show this**, and finding that out is why this
    // one exists: it orders two cards inside a Column the test itself builds,
    // so removing `SetupCard` from the real screen entirely leaves it green.
    // Proven by doing exactly that — the break came back passing.
    //
    // The claim is about `SettingsScreen`'s own child list, and that screen
    // needs nine stores to pump, so it is asserted where it actually lives.
    // Order is the point rather than presence: the Server card's diagnosis
    // says these settings are "below" it.
    final source =
        File('lib/features/settings/settings_screen.dart').readAsStringSync();

    final server = source.indexOf('const ServerCard()');
    final setup = source.indexOf('const SetupCard()');

    expect(server, greaterThan(-1), reason: 'ServerCard is not on the screen');
    expect(setup, greaterThan(-1), reason: 'SetupCard is not on the screen');
    expect(setup, greaterThan(server),
        reason: 'the sentence that sends people here says "below"');
  });

  testWidgets('the value is on the clipboard, not left to be typed', (t) async {
    // The values are a secret name, a project ref and a database password, and
    // the device reading this is most likely a phone. Typing
    // `SUPABASE_ACCESS_TOKEN` with a thumb is how a setup step gets abandoned.
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final backend = _Host(signedIn: true);
    await t.pumpWidget(host(backend));
    await t.pumpAndSettle();

    final first = backend.setupLinks().first;
    await t.tap(find.widgetWithText(
        TextButton, 'Copy ${first.copyLabel.toLowerCase()}'));
    await t.pumpAndSettle();

    expect(copied, first.copyValue);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('the two that unblock the deploy are both here', (t) async {
    // The ones the failing sentence is about. Named rather than counted,
    // because a count in prose is what was wrong with the sentence.
    final backend = _Host(signedIn: true);
    await t.pumpWidget(host(backend));
    await t.pumpAndSettle();

    expect(find.textContaining('SUPABASE_ACCESS_TOKEN'), findsOneWidget);
    expect(find.textContaining('xmjaqizlrlsvjbwqmtdo'), findsOneWidget);
  });

  testWidgets('every control clears the tap minimum', (t) async {
    final backend = _Host(signedIn: true);
    await t.pumpWidget(host(backend));
    await t.pumpAndSettle();

    for (final button in t.widgetList<TextButton>(find.byType(TextButton))) {
      expect(t.getSize(find.byWidget(button)).height,
          greaterThanOrEqualTo(kMinTouchTarget),
          reason: ((button.child as Text?)?.data) ?? '?');
    }
  });
}

/// A configured backend whose links are the real ones.
class _Host implements ShiftBackend {
  final bool signedIn;

  _Host({this.signedIn = false});

  @override
  bool get isConfigured => true;

  @override
  ShiftSession? get session => signedIn
      ? ShiftSession(
          account: const ShiftAccount(id: 'u1', email: 'a@example.com'),
          accessToken: 'token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        )
      : null;

  @override
  Stream<ShiftSession?> get sessionChanges => const Stream.empty();

  // Without this the store never leaves its `checking` phase and the card can
  // never appear — the test would be asserting the loading state.
  @override
  Future<ShiftSession?> restore() async => session;

  @override
  List<SetupLink> setupLinks() => [
        SetupLink(
          title: 'So the server keeps up with the app: an access token',
          action: 'Add secret',
          url: Uri.parse('https://github.test/settings/secrets/actions/new'),
          copyLabel: 'Secret name',
          copyValue: 'SUPABASE_ACCESS_TOKEN',
        ),
        SetupLink(
          title: 'So the server keeps up with the app: the project ref',
          action: 'Add variable',
          url: Uri.parse('https://github.test/settings/variables/actions/new'),
          copyLabel: 'Project ref',
          copyValue: 'xmjaqizlrlsvjbwqmtdo',
        ),
      ];

  @override
  Future<Membership> membership() async => Membership.none;

  @override
  Future<List<String>> includedProviders() async => const [];

  @override
  Future<bool> isAdmin() async => false;

  @override
  Future<List<ProviderKeyInfo>> listProviderKeys() async => const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
