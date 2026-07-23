import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injection seam: overridden in tests with a silent instance so no real audio
/// plugin is touched.
final notificationSoundProvider =
    Provider<NotificationSound>((ref) => NotificationSound());

/// Plays the in-app "new message" cue: a haptic tap plus a subtle chime. Fully
/// guarded — the AudioPlayer is created lazily on first use and any failure (asset
/// missing, muted, plugin unavailable) is swallowed so nothing ever throws.
class NotificationSound {
  NotificationSound();

  AudioPlayer? _player;

  Future<void> play() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {
      // haptics unavailable → ignore
    }
    try {
      if (_player == null) {
        _player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
        // Explicitly configure the audio session. On iOS, `playback` plays the chime
        // reliably (and activates the session); mix/duck so it coexists with other audio.
        await _player!.setAudioContext(
          AudioContext(
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: const {
                AVAudioSessionOptions.mixWithOthers,
                AVAudioSessionOptions.duckOthers,
              },
            ),
          ),
        );
      }
      // AssetSource resolves under assets/ → assets/sounds/new_message.wav
      await _player!.play(AssetSource('sounds/new_message.wav'), volume: 0.8);
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationSound: chime failed ($e)');
    }
  }
}
