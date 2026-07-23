import 'package:flutter/material.dart';

import 'skins.dart';
import 'tokens.dart';

/// Layer 3: theme assembly.
///
/// A skin preset supplies the neutral surface ramp + glass + effects; the
/// accent preset supplies [ColorScheme.primary]. Compose them with
/// [AppTheme.forSkin] — business UI never assembles themes itself.
abstract final class AppTheme {
  static const _animationDuration = Duration(milliseconds: 160);
  static const _fontFallback = <String>[
    'PingFang SC',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
    'Roboto',
    'sans-serif',
  ];

  static ThemeData forSkin(AppSkinPreset skin, AccentPreset accent) =>
      _build(skin.brightness, skin: skin, accent: accent.color);

  /// Convenience for callers that only know light/dark — prefer [forSkin].
  static ThemeData light(AccentPreset accent) =>
      forSkin(AppSkins.standard, accent);

  static ThemeData dark(AccentPreset accent) =>
      forSkin(AppSkins.deepNight, accent);

  static ThemeData _build(
    Brightness brightness, {
    required AppSkinPreset skin,
    required Color accent,
  }) {
    final dark = brightness == Brightness.dark;
    final canvas = skin.canvas;
    final surface = skin.surface;
    final elevated = skin.elevated;
    final overlay = skin.overlay;
    final glass = skin.glass;
    final effects = skin.effects;
    final foreground = glass.primaryText;
    final secondary = glass.secondaryText;
    final border = dark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);
    final hairline = dark
        ? Colors.white.withValues(alpha: 0.065)
        : Colors.black.withValues(alpha: 0.055);
    final disabledBorder = dark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.04);
    final subtle = dark
        ? Colors.white.withValues(alpha: 0.055)
        : Colors.black.withValues(alpha: 0.045);
    final disabledSubtle = dark
        ? Colors.white.withValues(alpha: 0.028)
        : Colors.black.withValues(alpha: 0.024);
    // fromSeed derives onPrimary for the seed's tonal primary, not for the
    // raw accent we force below — compute the matching contrast color.
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
          surface: surface,
        ).copyWith(
          primary: accent,
          onPrimary: onAccent,
          surface: surface,
          onSurface: foreground,
          onSurfaceVariant: secondary,
          outline: border,
          outlineVariant: hairline,
          surfaceContainerLowest: canvas,
          surfaceContainerLow: surface,
          surfaceContainer: elevated,
          surfaceContainerHigh: overlay,
          surfaceContainerHighest: overlay,
          // Kill M3 primary-tinted overlays that turn neutrals muddy.
          surfaceTint: Colors.transparent,
          scrim: Colors.black,
        );

    final baseTextTheme = ThemeData(
      brightness: brightness,
      fontFamily: '.SF Pro Text',
      fontFamilyFallback: _fontFallback,
    ).textTheme.apply(bodyColor: foreground, displayColor: foreground);
    final textTheme = baseTextTheme.copyWith(
      headlineLarge: baseTextTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineMedium: baseTextTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.55,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.25,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(color: secondary),
    );

    final focusOverlay = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.focused)) {
        return accent.withValues(alpha: 0.16);
      }
      if (states.contains(WidgetState.pressed)) {
        return foreground.withValues(alpha: 0.10);
      }
      if (states.contains(WidgetState.hovered)) {
        return foreground.withValues(alpha: 0.065);
      }
      return Colors.transparent;
    });
    final focusSide = WidgetStateProperty.resolveWith<BorderSide?>((states) {
      return states.contains(WidgetState.focused)
          ? BorderSide(color: accent, width: 2)
          : null;
    });
    final standardButtonStyle = ButtonStyle(
      animationDuration: _animationDuration,
      minimumSize: const WidgetStatePropertyAll(Size(36, 36)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      ),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      textStyle: WidgetStatePropertyAll(
        textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      iconSize: const WidgetStatePropertyAll(17),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: focusOverlay,
    );
    final pillBackground = WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return foreground.withValues(alpha: 0.022);
      }
      if (states.contains(WidgetState.pressed)) {
        return foreground.withValues(alpha: 0.11);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return foreground.withValues(alpha: 0.075);
      }
      return foreground.withValues(alpha: 0.045);
    });
    final quietPillBackground = WidgetStateProperty.resolveWith<Color>((
      states,
    ) {
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      if (states.contains(WidgetState.pressed)) {
        return foreground.withValues(alpha: 0.085);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return foreground.withValues(alpha: 0.055);
      }
      return foreground.withValues(alpha: 0.025);
    });
    final pillForeground = WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return secondary.withValues(alpha: 0.38);
      }
      return accent;
    });
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.control),
      borderSide: BorderSide(color: border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      cardColor: surface,
      fontFamily: '.SF Pro Text',
      fontFamilyFallback: _fontFallback,
      textTheme: textTheme,
      focusColor: foreground.withValues(alpha: 0.065),
      hoverColor: foreground.withValues(alpha: 0.055),
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      dividerColor: hairline,
      disabledColor: secondary.withValues(alpha: 0.38),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // Kill M3 primary-tinted overlays that turn white → dirty gray/orange.
      applyElevationOverlayColor: false,
      extensions: <ThemeExtension<dynamic>>[glass, effects],
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: canvas,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.42 : 0.16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
          side: BorderSide(color: border),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: secondary),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        modalElevation: 0,
        backgroundColor: elevated,
        modalBackgroundColor: elevated,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.42 : 0.16),
        dragHandleColor: secondary.withValues(alpha: 0.45),
        dragHandleSize: const Size(38, 4),
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
        constraints: const BoxConstraints(maxWidth: 760),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: overlay,
        actionTextColor: accent,
        disabledActionTextColor: secondary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: foreground),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.menu),
          side: BorderSide(color: border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: 0.14),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
          return IconThemeData(
            size: 21,
            color: states.contains(WidgetState.selected) ? accent : secondary,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
          return TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? foreground
                : secondary,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: 0.10),
        selectedIconTheme: IconThemeData(color: accent),
        selectedLabelTextStyle: TextStyle(
          color: accent,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        unselectedIconTheme: IconThemeData(color: secondary),
        unselectedLabelTextStyle: TextStyle(
          color: secondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: elevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.42 : 0.16),
        position: PopupMenuPosition.under,
        menuPadding: const EdgeInsets.all(6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.menu),
          side: BorderSide(color: border),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(elevated),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(
            Colors.black.withValues(alpha: dark ? 0.42 : 0.16),
          ),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.menu),
              side: BorderSide(color: border),
            ),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: subtle,
          border: inputBorder,
          enabledBorder: inputBorder,
          focusedBorder: inputBorder.copyWith(
            borderSide: BorderSide(color: accent, width: 2),
          ),
        ),
        menuStyle: MenuStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStatePropertyAll(elevated),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.menu),
              side: BorderSide(color: border),
            ),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: subtle,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: disabledBorder),
        ),
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: accent, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: TextStyle(color: secondary, fontWeight: FontWeight.w600),
        floatingLabelStyle: TextStyle(
          color: accent,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(color: secondary.withValues(alpha: 0.7)),
        prefixIconColor: secondary,
        suffixIconColor: secondary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: standardButtonStyle.copyWith(
          backgroundColor: pillBackground,
          foregroundColor: pillForeground,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: standardButtonStyle.copyWith(
          backgroundColor: pillBackground,
          foregroundColor: pillForeground,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: standardButtonStyle.copyWith(
          backgroundColor: quietPillBackground,
          foregroundColor: pillForeground,
          side: const WidgetStatePropertyAll(BorderSide.none),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: standardButtonStyle.copyWith(
          backgroundColor: quietPillBackground,
          foregroundColor: pillForeground,
          minimumSize: const WidgetStatePropertyAll(Size(36, 36)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          animationDuration: _animationDuration,
          minimumSize: const WidgetStatePropertyAll(Size.square(40)),
          iconSize: const WidgetStatePropertyAll(20),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) {
              return secondary.withValues(alpha: 0.38);
            }
            if (states.contains(WidgetState.selected)) {
              return accent;
            }
            return foreground;
          }),
          backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.pressed)) {
              return foreground.withValues(alpha: 0.10);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return foreground.withValues(alpha: 0.065);
            }
            return Colors.transparent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: const WidgetStatePropertyAll(CircleBorder()),
          side: focusSide,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: foreground.withValues(alpha: 0.045),
        foregroundColor: accent,
        shape: const CircleBorder(),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: secondary,
        textColor: foreground,
        selectedColor: accent,
        selectedTileColor: accent.withValues(alpha: 0.035),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        shape: const RoundedRectangleBorder(),
      ),
      // Quiet chrome for icons (both brands): light-weight outlines.
      iconTheme: IconThemeData(color: secondary, size: 20, weight: 300, fill: 0),
      primaryIconTheme: IconThemeData(
        color: accent,
        size: 20,
        weight: 300,
        fill: 0,
      ),
      checkboxTheme: CheckboxThemeData(
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: border, width: 1.4),
        fillColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(onAccent),
        overlayColor: focusOverlay,
      ),
      radioTheme: RadioThemeData(
        visualDensity: VisualDensity.compact,
        fillColor: WidgetStateProperty.resolveWith<Color>((states) {
          return states.contains(WidgetState.selected) ? accent : secondary;
        }),
        overlayColor: focusOverlay,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          return states.contains(WidgetState.selected) ? onAccent : secondary;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((states) {
          return states.contains(WidgetState.selected) ? accent : border;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: focusOverlay,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: border,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.12),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        showValueIndicator: ShowValueIndicator.never,
      ),
      chipTheme: ChipThemeData(
        elevation: 0,
        pressElevation: 0,
        backgroundColor: foreground.withValues(alpha: 0.025),
        selectedColor: accent.withValues(alpha: 0.09),
        disabledColor: disabledSubtle,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        labelStyle: textTheme.labelMedium?.copyWith(
          color: secondary,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: accent,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(size: 16, color: secondary),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        labelPadding: const EdgeInsets.symmetric(horizontal: 7),
        showCheckmark: false,
      ),
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        showDuration: const Duration(seconds: 3),
        decoration: BoxDecoration(
          color: overlay,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: foreground),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(5),
        radius: const Radius.circular(AppRadii.pill),
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          return secondary.withValues(
            alpha: states.contains(WidgetState.hovered) ? 0.55 : 0.30,
          );
        }),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: Colors.transparent,
      ),
    );
  }
}
