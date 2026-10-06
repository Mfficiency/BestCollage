/// BestCollage — 1–4 photo collages, built on the BestToDo app template.
///
/// Public barrel: import this to reuse the template's building blocks in your
/// own code (or when writing tests). App-specific configuration lives in
/// `src/app_config.dart` — the one file you edit to rebrand.
library best_collage;

export 'src/app.dart';
export 'src/app_config.dart';
export 'src/app_settings.dart';

export 'src/collage/collage_canvas.dart';
export 'src/collage/collage_controller.dart';
export 'src/collage/collage_models.dart';
export 'src/collage/collage_page.dart';
export 'src/collage/collage_saver.dart';
export 'src/collage/collage_tools.dart';
export 'src/collage/color_matrix.dart';
export 'src/collage/layouts.dart';
export 'src/collage/photo_loader.dart';

export 'src/models/intro_slide.dart';
export 'src/models/menu_entry.dart';
export 'src/models/start_page.dart';
export 'src/models/test_report.dart';

export 'src/services/backup_service.dart';
export 'src/services/log_service.dart';
export 'src/services/startup_time_service.dart';
export 'src/services/test_report_service.dart';

export 'src/theme/app_theme.dart';

export 'src/util/app_version.dart';
export 'src/util/date_time_format.dart';

export 'src/ui/about_page.dart';
export 'src/ui/app_logs_page.dart';
export 'src/ui/changelog_page.dart';
export 'src/ui/intro_page.dart';
export 'src/ui/app_drawer.dart';
export 'src/ui/settings_page.dart';
export 'src/ui/startup_times_page.dart';
export 'src/ui/subpage_app_bar.dart';
export 'src/ui/test_results_page.dart';
export 'src/ui/widgets/settings_section.dart';
export 'src/ui/widgets/spacing.dart';
export 'src/ui/widgets/version_banner.dart';
