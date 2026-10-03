import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/reader/reader_leaf_status.dart';
import '../utils/glass_config.dart';
import '../utils/reader_themes.dart';
import 'reader_top_information_bar.dart';
import 'reader_toolbar_preferences.dart';

typedef ReaderStatusBuilder =
    Widget Function(BuildContext context, TextStyle? style, Key? key);

class ReaderChromeOverlay extends StatelessWidget {
  const ReaderChromeOverlay({
    super.key,
    required this.palette,
    required this.visible,
    required this.title,
    required this.statusBottom,
    required this.statusBuilder,
    required this.onBack,
    required this.onBookmark,
    required this.onTableOfContents,
    required this.onSettings,
    required this.backTooltip,
    required this.bookmarkTooltip,
    required this.tableOfContentsTooltip,
    required this.settingsTooltip,
    required this.bookmarked,
    this.onReadAloud,
    this.readAloudTooltip,
    this.readAloudActive = false,
    this.onAskAi,
    this.askAiTooltip,
    this.bookmarkBusy = false,
    this.addToShelf = false,
    this.topKey,
    this.bottomKey,
    this.statusKey,
    this.showViewportStatus = true,
    this.showViewportTitle = false,
    this.viewportTitleTop = 0,
    this.viewportTitleKey,
    this.readerStatus,
    this.viewportStatusAlignment = Alignment.centerRight,
    this.viewportStatusHorizontalPadding = 14,
    this.showSettingsAction = true,
    this.onMore,
    this.chapterProgressLabel,
    this.chapterProgressAbovePageNumber = false,
  });

  final ReaderThemePalette palette;
  final bool visible;
  final String title;
  final double statusBottom;
  final ReaderStatusBuilder statusBuilder;
  final VoidCallback onBack;
  final VoidCallback? onBookmark;
  final VoidCallback? onTableOfContents;
  final VoidCallback onSettings;
  final VoidCallback? onReadAloud;
  final VoidCallback? onAskAi;
  final String? askAiTooltip;
  final String backTooltip;
  final String bookmarkTooltip;
  final String tableOfContentsTooltip;
  final String settingsTooltip;
  final String? readAloudTooltip;
  final bool bookmarked;
  final bool readAloudActive;
  final bool bookmarkBusy;
  final bool addToShelf;
  final Key? topKey;
  final Key? bottomKey;
  final Key? statusKey;
  final bool showViewportStatus;
  final bool showViewportTitle;
  final double viewportTitleTop;
  final Key? viewportTitleKey;
  final ReaderLeafStatusData? readerStatus;
  final AlignmentGeometry viewportStatusAlignment;
  final double viewportStatusHorizontalPadding;
  final bool showSettingsAction;
  final VoidCallback? onMore;
  final String? chapterProgressLabel;
  final bool chapterProgressAbovePageNumber;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (chapterProgressLabel != null && !visible)
          Positioned(
            left: 24,
            bottom: statusBottom + (chapterProgressAbovePageNumber ? 16 : 0),
            child: IgnorePointer(
              child: Text(
                chapterProgressLabel!,
                key: const ValueKey('reader-chapter-progress'),
                style: textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  height: 1,
                  color: palette.secondaryText.withValues(alpha: 0.66),
                ),
              ),
            ),
          ),
        if (showViewportTitle)
          Positioned(
            left: 30,
            right: 30,
            top: viewportTitleTop,
            child: IgnorePointer(
              child: AnimatedOpacity(
                key: viewportTitleKey,
                opacity: visible ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: ReaderTopInformationBar(
                  palette: palette,
                  title: title,
                  status: readerStatus,
                ),
              ),
            ),
          ),
        if (showViewportStatus)
          Positioned(
            left: 0,
            right: 0,
            bottom: statusBottom,
            child: IgnorePointer(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: viewportStatusHorizontalPadding,
                ),
                child: Align(
                  alignment: viewportStatusAlignment,
                  child: statusBuilder(
                    context,
                    textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      height: 1,
                      color: palette.secondaryText.withValues(
                        alpha: visible ? 0 : 0.58,
                      ),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    statusKey,
                  ),
                ),
              ),
            ),
          ),
        if (!showViewportStatus && statusKey != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: statusBottom,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: 0,
                  child: statusBuilder(context, null, statusKey),
                ),
              ),
            ),
          ),
        AnimatedPositioned(
          key: topKey,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          left: 20,
          right: 20,
          top: visible ? 10 : -130,
          child: SafeArea(
            bottom: false,
            child: ReaderControlBar(
              palette: palette,
              isTopBar: true,
              child: SizedBox(
                height: 58,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      ReaderControlIconButton(
                        palette: palette,
                        onPressed: onBack,
                        tooltip: backTooltip,
                        icon: Icons.arrow_back_rounded,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                            color: palette.text,
                          ),
                        ),
                      ),
                      ReaderControlIconButton(
                        palette: palette,
                        onPressed: bookmarkBusy ? null : onBookmark,
                        tooltip: bookmarkTooltip,
                        icon: addToShelf
                            ? Icons.library_add_outlined
                            : bookmarked
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                      ),
                      ReaderControlIconButton(
                        key: const ValueKey('reader-book-settings'),
                        palette: palette,
                        onPressed: onMore ?? onSettings,
                        tooltip: onMore != null ? '书籍设置' : settingsTooltip,
                        icon: Icons.more_horiz_rounded,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        ReaderToolbarBuilder(builder: _bottomBar),
      ],
    );
  }

  Widget _bottomBar(BuildContext context, ReaderToolbarPreferences prefs) {
    final actions = prefs.order
        .where(
          (action) =>
              !prefs.hidden.contains(action) &&
              switch (action) {
                ReaderToolbarAction.aloud => onReadAloud != null,
                ReaderToolbarAction.ai => onAskAi != null,
                ReaderToolbarAction.settings => showSettingsAction,
                ReaderToolbarAction.catalog => true,
              },
        )
        .toList();
    if (!prefs.enabled || actions.isEmpty) return const SizedBox.shrink();
    return AnimatedPositioned(
      key: bottomKey,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      left: 22,
      right: 22,
      bottom: visible ? 16 : -150,
      child: SafeArea(
        top: false,
        child: ReaderControlBar(
          palette: palette,
          isTopBar: false,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final action in actions)
                  _bottomAction(action, prefs.labels),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomAction(ReaderToolbarAction action, bool labels) {
    final (callback, label, icon) = switch (action) {
      ReaderToolbarAction.catalog => (
        onTableOfContents,
        tableOfContentsTooltip,
        Icons.format_list_bulleted_rounded,
      ),
      ReaderToolbarAction.aloud => (
        onReadAloud,
        readAloudTooltip ?? action.label,
        readAloudActive ? Icons.graphic_eq_rounded : Icons.headphones_rounded,
      ),
      ReaderToolbarAction.ai => (
        onAskAi,
        askAiTooltip ?? action.label,
        Icons.auto_awesome_outlined,
      ),
      ReaderToolbarAction.settings => (
        onSettings,
        settingsTooltip,
        Icons.tune_rounded,
      ),
    };
    final button = ReaderControlIconButton(
      palette: palette,
      onPressed: callback,
      tooltip: label,
      icon: icon,
    );
    if (!labels) return button;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        Text(action.label, style: TextStyle(fontSize: 10, color: palette.text)),
      ],
    );
  }
}

class ReaderControlBar extends StatelessWidget {
  const ReaderControlBar({
    super.key,
    required this.palette,
    required this.isTopBar,
    required this.child,
  });

  final ReaderThemePalette palette;
  final bool isTopBar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(999);
    final blurEnabled = !GlassEffectConfig.shouldDisableBlur;
    // 不叠加预设，直接使用与悬浮导航栏/首页顶栏一致的标准玻璃参数
    final config = GlassEffectHelper.getReadingControlConfig(
      isTopBar: isTopBar,
      brightness: palette.brightness,
    );
    final surfaceOpacity = blurEnabled ? config['opacity']! : 1.0;
    final cleanSurface = blurEnabled
        ? GlassEffectConfig.chromeBaseColor(
            palette.controlBar,
            palette.brightness,
            lightBlend: 0.28,
          )
        : palette.controlBar;
    final highlight = blurEnabled
        ? Color.lerp(
            cleanSurface,
            Colors.white,
            palette.brightness == Brightness.dark ? 0.06 : 0.1,
          )!
        : cleanSurface;
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            highlight.withValues(
              alpha: (surfaceOpacity + (blurEnabled ? 0.08 : 0.0)).clamp(
                0.0,
                1.0,
              ),
            ),
            cleanSurface.withValues(
              alpha: (surfaceOpacity - (blurEnabled ? 0.02 : 0.0)).clamp(
                0.0,
                1.0,
              ),
            ),
          ],
        ),
        border: Border.all(
          color: blurEnabled
              ? Color.lerp(
                  palette.border,
                  Colors.white,
                  palette.brightness == Brightness.dark ? 0.16 : 0.14,
                )!.withValues(
                  alpha: palette.brightness == Brightness.light ? 0.28 : 0.54,
                )
              : palette.border,
          width: 1,
        ),
      ),
      child: Material(color: Colors.transparent, child: child),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: blurEnabled
                ? GlassEffectConfig.chromeShadowColor(
                    source: palette.shadow,
                    brightness: palette.brightness,
                    darkOpacity: 0.46,
                  )
                : palette.shadow.withValues(
                    alpha: palette.brightness == Brightness.dark ? 0.46 : 0.22,
                  ),
            blurRadius: blurEnabled && palette.brightness == Brightness.light
                ? 24
                : 32,
            spreadRadius: -5,
            offset: Offset(
              0,
              blurEnabled && palette.brightness == Brightness.light ? 8 : 16,
            ),
          ),
          if (!blurEnabled || palette.brightness == Brightness.dark)
            BoxShadow(
              color: palette.shadow.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: blurEnabled
            ? BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: config['blur']!,
                  sigmaY: config['blur']!,
                ),
                child: panel,
              )
            : panel,
      ),
    );
  }
}

class ReaderControlIconButton extends StatelessWidget {
  const ReaderControlIconButton({
    super.key,
    required this.palette,
    required this.onPressed,
    required this.tooltip,
    required this.icon,
  });

  final ReaderThemePalette palette;
  final VoidCallback? onPressed;
  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final glassEnabled = !GlassEffectConfig.shouldDisableBlur;
    final cleanControlFill = glassEnabled
        ? GlassEffectConfig.chromeBaseColor(
            palette.controlFill,
            palette.brightness,
            lightBlend: 0.22,
          )
        : palette.controlFill;
    return IconButton.filledTonal(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      style: IconButton.styleFrom(
        foregroundColor: palette.text,
        backgroundColor: cleanControlFill.withValues(
          alpha: glassEnabled
              ? (palette.brightness == Brightness.light ? 0.76 : 0.58)
              : 1.0,
        ),
        minimumSize: const Size.square(44),
        maximumSize: const Size.square(44),
        padding: EdgeInsets.zero,
        side: BorderSide(
          color: glassEnabled
              ? Color.lerp(palette.border, Colors.white, 0.12)!.withValues(
                  alpha: palette.brightness == Brightness.light ? 0.28 : 0.48,
                )
              : palette.border,
          width: 0.8,
        ),
        shape: const CircleBorder(),
      ),
    );
  }
}
