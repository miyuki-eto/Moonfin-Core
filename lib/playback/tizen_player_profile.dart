import '../preference/user_preferences.dart';
import 'audio_capability_profile.dart';
import 'device_profile_builder.dart';

/// Baseline BU8000 capabilities; no guessed DTS, TrueHD, Dolby Vision or
/// passthrough support. Samsung decodes/downmixes Dolby audio for its selected
/// sound output; the two built-in speakers do not limit accepted input to AAC.
Map<String, dynamic> buildTizenPlayerProfile(UserPreferences prefs) {
  const audio = AudioCapabilityProfile(
    canDecodeAc3: true,
    canDecodeEac3: true,
    canDecodeDts: false,
    canDecodeDtsHd: false,
    canDecodeTrueHd: false,
    canDecodeFlac: true,
    canPassthroughAc3: false,
    canPassthroughEac3: false,
    canPassthroughDts: false,
    canPassthroughDtsHd: false,
    canPassthroughTrueHd: false,
    maxPcmChannels: 2,
    activeRouteType: AudioRouteType.speaker,
    routeSupportsHdAudio: false,
  );
  final profile = DeviceProfileBuilder.build(
    maxBitrateMbps: int.tryParse(prefs.get(UserPreferences.maxBitrate)),
    maxResolution: prefs.get(UserPreferences.maxVideoResolution),
    audioCapabilityProfile: audio,
    playerDecodesTrueHd: false,
    playerDecodesStereoTrueHd: false,
    maxAudioChannels: 6,
    pgsDirectPlay: true,
    supportsExternalPgsSubtitles: true,
    assDirectPlay: false,
    supportsAvc: true,
    avcMainLevel: 51,
    supportsHevc: true,
    supportsHevcMain10: true,
    hevcMainLevel: 153,
    supportsHevcHdr10: true,
    supportsHevcHdr10Plus: true,
    maxResolutionAvcWidth: 3840,
    maxResolutionAvcHeight: 2160,
    maxResolutionHevcWidth: 3840,
    maxResolutionHevcHeight: 2160,
    directPlayVideoContainers: 'mkv,mp4,m4v,mov,ts,mpegts,hls',
  );
  // The native plugin supplies embedded text. Sidecars use its SRT/VTT
  // parser; PGS is drawn by Flutter. TTML, ASS and other bitmap formats
  // must still be converted by the server.
  final subtitles = profile['SubtitleProfiles'] as List;
  subtitles.removeWhere(
    (entry) =>
        entry is Map &&
        ((entry['Method'] == 'External' &&
                !{
                  'srt',
                  'subrip',
                  'vtt',
                  'webvtt',
                  'pgs',
                  'pgssub',
                }.contains(entry['Format'])) ||
            (entry['Method'] == 'Embed' &&
                {
                  'dvbsub',
                  'dvdsub',
                  'idx',
                  'pgs',
                  'pgssub',
                }.contains(entry['Format']))),
  );
  return profile;
}
