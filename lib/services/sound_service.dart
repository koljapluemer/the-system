import 'package:audioplayers/audioplayers.dart';

/// Plays the short chime bundled at assets/sounds/block_done.mp3, used by the
/// Make a Block flow when its 25-minute timer runs out. A fresh AudioPlayer
/// per call keeps this stateless and safe to call repeatedly without
/// worrying about a shared player's lifecycle.
Future<void> playBlockDoneSound() async {
  final player = AudioPlayer();
  await player.play(AssetSource('sounds/block_done.mp3'));
}
