import 'language_matching.dart';

/// A numeric stream index is only valid for one server response. Save the
/// selected track's meaning so adding a sidecar cannot select another language.
Map<String, dynamic>? itemTrackSelection(
  List<Map<String, dynamic>> streams,
  int? index,
) {
  if (index == -1) return const {'version': 1, 'off': true};
  if (index == null || index < 0) return null;
  final matches = streams.where((stream) => stream['Index'] == index).toList();
  if (matches.length != 1) return null;
  return {'version': 1, 'identity': _identity(matches.single)};
}

int? restoreItemTrackSelection(
  Map<String, dynamic>? saved,
  List<Map<String, dynamic>> streams,
) {
  if (saved?['version'] != 1) return null;
  if (saved?['off'] == true) return -1;
  final identity = saved?['identity'];
  if (identity is! Map) return null;
  final matches = streams.where((stream) {
    final current = _identity(stream);
    return current.length == identity.length &&
        current.entries.every((entry) => identity[entry.key] == entry.value);
  }).toList();
  // An absent or ambiguous identity returns to language defaults. Position
  // cannot distinguish two equally labelled tracks after a source change.
  return matches.length == 1 ? matches.single['Index'] as int? : null;
}

Map<String, dynamic> _identity(Map<String, dynamic> stream) => {
  'Type': stream['Type'],
  'Language': toIso3Language(normalizeLanguage(stream['Language'] as String?)),
  'Title': (stream['Title'] as String? ?? '').trim().toLowerCase(),
  'Codec': (stream['Codec'] as String? ?? '').toLowerCase(),
  'IsExternal': stream['IsExternal'] == true,
  'IsForced': stream['IsForced'] == true,
  'IsHearingImpaired': stream['IsHearingImpaired'] == true,
  'IsCommentary': stream['IsCommentary'] == true,
  'IsAudioDescription': stream['IsAudioDescription'] == true,
  if (stream['Type'] == 'Audio') 'Channels': stream['Channels'],
};
