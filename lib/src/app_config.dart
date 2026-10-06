import 'package:flutter/material.dart';

import 'models/intro_slide.dart';
import 'models/menu_entry.dart';
import 'models/start_page.dart';

/// ============================================================================
/// THE ONE FILE YOU EDIT TO REBRAND THIS TEMPLATE.
/// ============================================================================
///
/// Everything app-specific lives here: name, colours, intro, start pages,
/// notification defaults, backup identity and the menu. No other file needs to
/// change to stand up a new app. See ../../TEMPLATE_GUIDE.md for the checklist.
///
/// Nothing here hard-codes a *version* — the running version comes from
/// package_info_plus (see [AppVersion]) and the tooling reads pubspec.yaml.
class AppConfig {
  AppConfig._();

  // --- Identity -------------------------------------------------------------

  /// Shown on the main menu header, the About page and the window title.
  static const String appName = 'BestCollage';

  /// One-line tagline under the app name on the main menu.
  static const String tagline = 'Photo collages in a few taps';

  /// About-page body. Plain multi-line text; keep it human, not marketing.
  static const String aboutText =
      'BestCollage puts 1 to 4 photos together into one picture.\n\n'
      'Pick a layout and slide the dividers to resize the photos, pinch to '
      'zoom and crop, rotate or mirror them, and change the colour tone, hue, '
      'saturation, brightness and warmth — for all photos at once or one at a '
      'time. Turn on the date each photo was taken (dd.mm.yy), drag it where '
      'you want it and pinch to resize it. Save makes a new picture; your '
      'originals are never changed.\n\n'
      'No ads, no tracking, no accounts. Photos never leave your phone.';

  /// Opened by the About page's "Update app" button. Point it at your store
  /// listing (Play Store, App Store) or a download page.
  static const String updateUrl =
      'https://github.com/Mfficiency/BestCollage/tree/dev/github_releases';

  // --- Theme ----------------------------------------------------------------

  /// Seed colour for the Material 3 colour scheme. Change this one value to
  /// recolour the whole app. The minimalist theme ignores it by design.
  static const Color seedColor = Color(0xFF005FDD);

  // --- Intro ----------------------------------------------------------------

  /// Slides shown on first launch (and via About → "Replay introduction").
  /// Add, remove or reorder freely.
  static const List<IntroSlide> introSlides = [
    IntroSlide(
      icon: Icons.dashboard_customize_outlined,
      title: 'Pick 1 to 4 photos',
      body: 'Choose a layout, then drag the handles between photos to resize '
          'them.',
    ),
    IntroSlide(
      icon: Icons.crop_rotate,
      title: 'Crop, rotate, recolour',
      body: 'Pinch to zoom, drag to move, and tune the colours of every photo '
          'together or one at a time.',
    ),
    IntroSlide(
      icon: Icons.event,
      title: 'Add the date',
      body: 'Stamp the date each photo was taken (dd.mm.yy), place it anywhere '
          'and save the collage as a new picture.',
    ),
  ];

  // --- Start pages ----------------------------------------------------------

  /// Pages the user may pick as the app's launch screen (Settings → Startup).
  /// The first entry is the default. Keys are persisted, so keep them stable.
  /// The `builder` returns the page pushed on launch (the main menu is always
  /// the root, so backing out of a start page lands on the menu).
  static List<StartPage> startPages = defaultStartPages;

  // --- Notification defaults -------------------------------------------------
  //
  // The template stores notification *preferences* (it does not bundle a
  // notifications plugin — wire one in where NotificationPrefs is read). These
  // are the out-of-the-box defaults for a fresh install.

  /// Default delay (seconds) before a manually-triggered notification fires.
  static const int defaultNotificationDelaySeconds = 300; // 05:00

  /// Whether quiet hours are on by default.
  static const bool quietHoursEnabledByDefault = false;

  /// Default quiet-hours window, in minutes since midnight.
  static const int quietHoursStartMinutes = 22 * 60; // 22:00
  static const int quietHoursEndMinutes = 7 * 60; // 07:00

  // --- Backups --------------------------------------------------------------

  /// Written into every backup file and checked on import so one app never
  /// imports another app's export. Change it per app.
  static const String backupAppId = 'best_collage';

  /// Bump when the backup *shape* changes so old files can be migrated. The
  /// importer tolerates older versions; see [BackupService].
  static const int backupSchemaVersion = 1;

  // --- Menu -----------------------------------------------------------------

  /// Extra, app-specific entries added to the main menu above the built-in
  /// technical pages. Point each at your own feature pages.
  static const List<MenuEntry> customMenuEntries = [
    // MenuEntry(icon: Icons.checklist, label: 'Tasks', routeBuilder: TasksPage.new),
  ];
}
