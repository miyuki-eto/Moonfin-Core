import '../config/app_features.dart';

/// This fork has fixed layouts and does not offer application or browse-display
/// settings. Existing preferences remain readable for saved installations.
bool get showAppSettings => AppFeatures.has(AppFeature.settings);
