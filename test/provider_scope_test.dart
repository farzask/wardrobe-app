import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Guards the provider-scoping invariant that `main.dart` depends on.
///
/// The bug these tests exist for: per-user view models were installed under `MaterialApp.home`.
/// `Navigator.push` mounts routes on MaterialApp's Navigator, which sits *above* `home`, so every
/// pushed screen was a sibling of the provider scope rather than a descendant and threw
/// ProviderNotFoundException the first time the user navigated.
///
/// It never showed up in the wardrobe screen itself, only after a push — which is why it survived
/// to a real device. These tests pin the structural rule so a future refactor cannot quietly
/// reintroduce it.
class _Counter extends ChangeNotifier {
  int value = 0;
}

/// Mirrors the real app's shape: providers wrapped around the Navigator via `builder`.
Widget appWithScopeAboveNavigator({required Widget home}) {
  return ChangeNotifierProvider(
    create: (_) => _Counter(),
    child: MaterialApp(
      builder: (context, navigator) => ChangeNotifierProvider(
        create: (_) => _Counter(),
        child: navigator!,
      ),
      home: home,
    ),
  );
}

/// The broken shape, kept deliberately so the failure mode stays documented and provable.
Widget appWithScopeUnderHome({required Widget home}) {
  return MaterialApp(
    home: ChangeNotifierProvider(
      create: (_) => _Counter(),
      child: home,
    ),
  );
}

class _PushesARoute extends StatelessWidget {
  const _PushesARoute();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const _ReadsTheProvider()),
          ),
          child: const Text('push'),
        ),
      ),
    );
  }
}

class _ReadsTheProvider extends StatelessWidget {
  const _ReadsTheProvider();

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Text('value ${context.watch<_Counter>().value}'));
  }
}

void main() {
  testWidgets('a provider above the Navigator is visible to a pushed route', (tester) async {
    await tester.pumpWidget(appWithScopeAboveNavigator(home: const _PushesARoute()));

    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('value 0'), findsOneWidget);
  });

  testWidgets('a provider under home is NOT visible to a pushed route', (tester) async {
    // The exact failure that reached the device. Asserted rather than described, so the reason
    // `main.dart` uses `builder` is verifiable instead of a claim in a comment.
    await tester.pumpWidget(appWithScopeUnderHome(home: const _PushesARoute()));

    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isA<ProviderNotFoundException>());
  });

  testWidgets('a modal route also reaches a provider above the Navigator', (tester) async {
    // showModalBottomSheet mounts on the Navigator too — the wardrobe filter sheet relies on this.
    await tester.pumpWidget(appWithScopeAboveNavigator(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const _ReadsTheProvider(),
            ),
            child: const Text('open sheet'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('value 0'), findsOneWidget);
  });
}
