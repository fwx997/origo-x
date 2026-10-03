import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xxread/core/reader/reader_layout.dart';
import 'package:xxread/core/reader/reader_settings.dart';

void main() {
  test('reader interaction defaults and changes persist', () async {
    SharedPreferences.setMockInitialValues({});
    const store = ReaderSettingsStore();
    final initial = await store.load();
    expect(initial.textSelectionEnabled, isFalse);
    expect(initial.edgeSwipeBackEnabled, isTrue);
    expect(initial.hideBarsOnVerticalSwipe, isTrue);
    await store.save(
      initial.copyWith(
        textSelectionEnabled: true,
        edgeSwipeBackEnabled: false,
        hideBarsOnVerticalSwipe: false,
      ),
    );
    final restored = await store.load();
    expect(restored.textSelectionEnabled, isTrue);
    expect(restored.edgeSwipeBackEnabled, isFalse);
    expect(restored.hideBarsOnVerticalSwipe, isFalse);
  });
  test(
    'text appearance and chapter progress persist with safe bounds',
    () async {
      SharedPreferences.setMockInitialValues({});
      const store = ReaderSettingsStore();
      final settings = (await store.load()).copyWith(
        textBrightness: 0.55,
        dimNightText: false,
        fontWeight: 600,
        showChapterProgress: false,
      );
      await store.save(settings);
      final loaded = await store.load();
      expect(loaded.textBrightness, 0.55);
      expect(loaded.dimNightText, isFalse);
      expect(loaded.fontWeight, 600);
      expect(loaded.showChapterProgress, isFalse);
      expect(
        settings.copyWith(fontWeight: 999, textBrightness: -2).fontWeight,
        700,
      );
      expect(settings.copyWith(textBrightness: -2).textBrightness, 0.3);
    },
  );

  test('defaults page turning to horizontal slide', () async {
    SharedPreferences.setMockInitialValues({});

    final settings = await const ReaderSettingsStore().load();

    expect(settings.pageMode, ReaderPageMode.horizontalSlide);
    expect(settings.letterSpacing, ReaderSettings.defaultLetterSpacing);
    expect(settings.textAlignment, ReaderTextAlignment.natural);
    expect(
      await const ReaderSettingsStore().loadTxtChapterTitlePageEnabled(),
      isTrue,
    );
  });

  test(
    'migrates legacy vertical spacing into shared independent margins',
    () async {
      SharedPreferences.setMockInitialValues({
        ReaderSettingsStore.legacyVerticalMarginKey: 38.0,
      });

      final settings = await const ReaderSettingsStore().load(
        fallbackPageMode: ReaderPageMode.verticalScroll,
      );

      expect(settings.topMargin, 14);
      expect(settings.bottomMargin, 10);
      expect(settings.tabletTwoPageEnabled, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(ReaderSettingsStore.topMarginKey), 14);
      expect(prefs.getDouble(ReaderSettingsStore.bottomMarginKey), 10);
    },
  );

  test('persists the TXT chapter title page preference', () async {
    SharedPreferences.setMockInitialValues({});
    const store = ReaderSettingsStore();

    await store.saveTxtChapterTitlePageEnabled(false);

    expect(await store.loadTxtChapterTitlePageEnabled(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(ReaderSettingsStore.txtChapterTitlePageKey), isFalse);
  });

  test('persists one settings model for every reader entry', () async {
    SharedPreferences.setMockInitialValues({});
    const store = ReaderSettingsStore();
    const settings = ReaderSettings(
      fontSize: 22,
      lineHeight: 1.8,
      letterSpacing: 0.6,
      textAlignment: ReaderTextAlignment.justified,
      horizontalMargin: 20,
      topMargin: 7,
      bottomMargin: 3,
      themeId: 'mist',
      pageMode: ReaderPageMode.pageCurl,
      firstLineIndent: 3,
      paragraphSpacing: 1,
      pullBookmarkEnabled: true,
      tapPageAnimationEnabled: false,
      tabletTwoPageEnabled: false,
    );

    await store.save(settings);
    final restored = await store.load(
      fallbackPageMode: ReaderPageMode.verticalScroll,
    );

    expect(restored.fontSize, 22);
    expect(restored.letterSpacing, 0.6);
    expect(restored.textAlignment, ReaderTextAlignment.justified);
    expect(restored.topMargin, 7);
    expect(restored.bottomMargin, 3);
    expect(restored.themeId, 'mist');
    expect(restored.pageMode, ReaderPageMode.pageCurl);
    expect(restored.firstLineIndent, 3);
    expect(restored.paragraphSpacing, 1);
    expect(restored.pullBookmarkEnabled, isTrue);
    expect(restored.tapPageAnimationEnabled, isFalse);
    expect(restored.tabletTwoPageEnabled, isFalse);
  });

  test('allows a zero horizontal page margin', () async {
    SharedPreferences.setMockInitialValues({
      ReaderSettingsStore.horizontalMarginKey: 0.0,
    });

    final restored = await const ReaderSettingsStore().load(
      fallbackPageMode: ReaderPageMode.verticalScroll,
    );

    expect(restored.horizontalMargin, 0);
    expect(restored.copyWith(horizontalMargin: -1).horizontalMargin, 0);
  });

  test(
    'shares the chapter-scoped scrolling preference across readers',
    () async {
      SharedPreferences.setMockInitialValues({});
      const store = ReaderSettingsStore();

      expect(await store.loadScrollByChapter(), isTrue);

      await store.saveScrollByChapter(false);

      expect(await store.loadScrollByChapter(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(ReaderSettingsStore.scrollByChapterKey), isFalse);
    },
  );

  test('clamps typography and interaction settings', () async {
    SharedPreferences.setMockInitialValues({
      ReaderSettingsStore.firstLineIndentKey: 20,
      ReaderSettingsStore.paragraphSpacingKey: -3,
      ReaderSettingsStore.letterSpacingKey: 9.0,
      ReaderSettingsStore.textAlignmentKey: 'unknown',
      'native_reader_page_turn_style': 'cylinder',
    });

    final restored = await const ReaderSettingsStore().load(
      fallbackPageMode: ReaderPageMode.verticalScroll,
    );

    expect(restored.firstLineIndent, 4);
    expect(restored.paragraphSpacing, 0);
    expect(restored.letterSpacing, ReaderSettings.maxLetterSpacing);
    expect(restored.textAlignment, ReaderTextAlignment.natural);
    expect(restored.pullBookmarkEnabled, isFalse);
    expect(restored.tapPageAnimationEnabled, isTrue);
    expect(restored.tabletTwoPageEnabled, isTrue);
    expect(restored.copyWith(firstLineIndent: -1).firstLineIndent, 0);
    expect(restored.copyWith(paragraphSpacing: 9).paragraphSpacing, 2);
    expect(
      restored.copyWith(letterSpacing: -1).letterSpacing,
      ReaderSettings.minLetterSpacing,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('native_reader_page_turn_style'), isNull);
  });
}
