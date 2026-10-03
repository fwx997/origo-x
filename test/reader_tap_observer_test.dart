import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xxread/widgets/reader_tap_observer.dart';

void main() {
  testWidgets('vertical swipe reports once without swallowing scrolling', (
    tester,
  ) async {
    var hides = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderTapObserver(
          onTap: (_) {},
          onVerticalSwipe: () => hides++,
          child: ListView(
            controller: controller,
            children: const [SizedBox(height: 3000)],
          ),
        ),
      ),
    );
    await tester.dragFrom(const Offset(200, 400), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(hides, 1);
    expect(controller.offset, greaterThan(0));
    await tester.dragFrom(const Offset(200, 400), const Offset(180, 0));
    expect(hides, 1);
  });

  testWidgets('left edge returns without turning the underlying page', (
    tester,
  ) async {
    var exits = 0;
    final controller = PageController(initialPage: 1);
    addTearDown(controller.dispose);
    Widget reader(bool enabled) => MaterialApp(
      home: ReaderTapObserver(
        onTap: (_) {},
        onEdgeBack: enabled ? () => exits++ : null,
        child: PageView(
          controller: controller,
          children: const [SizedBox.expand(), SizedBox.expand()],
        ),
      ),
    );
    await tester.pumpWidget(reader(true));
    await tester.dragFrom(const Offset(8, 200), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(exits, 1);
    expect(controller.page, 1);
    await tester.dragFrom(const Offset(8, 200), const Offset(-120, 0));
    expect(exits, 1);
    await tester.pumpWidget(reader(false));
    await tester.flingFrom(const Offset(8, 200), const Offset(600, 0), 1500);
    await tester.pumpAndSettle();
    expect(exits, 1);
    expect(controller.page, 0);
  });
  testWidgets('reader tap observer emits one short stationary tap', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderTapObserver(
          onTap: (_) => taps++,
          child: const SizedBox.expand(),
        ),
      ),
    );

    await tester.tapAt(const Offset(100, 100));

    expect(taps, 1);
  });

  testWidgets('reader tap observer tolerates normal finger jitter', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderTapObserver(
          onTap: (_) => taps++,
          child: const SizedBox.expand(),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(100, 100));
    await gesture.moveBy(const Offset(12, 0));
    await gesture.up();
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('reader tap observer leaves drags and long presses alone', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderTapObserver(
          onTap: (_) => taps++,
          child: const SizedBox.expand(),
        ),
      ),
    );

    await tester.dragFrom(const Offset(100, 100), const Offset(30, 0));
    final longPress = await tester.startGesture(const Offset(100, 100));
    await tester.pump(const Duration(milliseconds: 500));
    await longPress.up();

    expect(taps, 0);
  });
}
