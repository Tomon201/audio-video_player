import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/media_provider.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  bool _showControls = true;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaProvider>(
      builder: (BuildContext context, MediaProvider provider, Widget? child) {
        final currentItem = provider.currentPlaying;
        final isVid = currentItem?.isVideo ?? false;

        return Scaffold(
          backgroundColor: const Color(0xFF0F0F0F),
          appBar: isVid && !_showControls
              ? null
              : AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 32, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              currentItem?.folderName ?? 'Плеер',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            centerTitle: true,
          ),
          body: isVid
              ? GestureDetector(
            onTap: () {
              setState(() {
                _showControls = !_showControls;
              });
            },
            child: Stack(
              children: [
                Center(
                  child: provider.isVideoInitializing
                      ? const CircularProgressIndicator(color: Colors.redAccent)
                      : (provider.videoController != null &&
                      provider.videoController!.value.isInitialized
                      ? AspectRatio(
                    aspectRatio: provider.videoController!.value.aspectRatio,
                    child: VideoPlayer(provider.videoController!),
                  )
                      : const Icon(Icons.broken_image, size: 64, color: Colors.grey)),
                ),
                if (_showControls)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black45,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const SizedBox(height: 44),
                            Column(
                              children: [
                                Text(
                                  currentItem?.title ?? '',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  currentItem?.folderName ?? '',
                                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                            _buildControls(provider, isVid: true),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          )
              : Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: const Center(
                      child: Icon(Icons.music_note, size: 96, color: Colors.white54),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  currentItem?.title ?? '',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  currentItem?.folderName ?? '',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _buildControls(provider, isVid: false),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControls(MediaProvider provider, {required bool isVid}) {
    return StreamBuilder<Duration>(
      stream: isVid && provider.videoController != null
          ? Stream.periodic(
        const Duration(milliseconds: 200),
            (_) => provider.videoController?.value.position ?? Duration.zero,
      )
          : provider.audioPlayer.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = isVid && provider.videoController != null && provider.videoController!.value.isInitialized
            ? provider.videoController!.value.duration
            : (provider.audioPlayer.duration ?? Duration.zero);

        return Column(
          children: [
            Slider(
              activeColor: Colors.white,
              inactiveColor: Colors.grey[800],
              min: 0.0,
              max: duration.inMilliseconds.toDouble() > 0
                  ? duration.inMilliseconds.toDouble()
                  : 1.0,
              value: position.inMilliseconds.toDouble().clamp(
                0.0,
                duration.inMilliseconds.toDouble() > 0
                    ? duration.inMilliseconds.toDouble()
                    : 1.0,
              ),
              onChanged: (val) {
                final targetPos = Duration(milliseconds: val.toInt());
                if (isVid && provider.videoController != null) {
                  provider.videoController!.seekTo(targetPos);
                } else {
                  provider.audioPlayer.seek(targetPos);
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(position), style: const TextStyle(color: Colors.grey)),
                  Text(_formatDuration(duration), style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                isVid
                    ? IconButton(
                  icon: Icon(
                    provider.isVideoLooping ? Icons.repeat : Icons.repeat_outlined,
                    color: provider.isVideoLooping ? Colors.redAccent : Colors.white,
                  ),
                  onPressed: () => provider.toggleVideoLoop(),
                )
                    : IconButton(
                  icon: Icon(
                    provider.isShuffle ? Icons.shuffle : Icons.shuffle_outlined,
                    color: provider.isShuffle ? Colors.redAccent : Colors.white,
                  ),
                  onPressed: () => provider.toggleShuffle(),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white, size: 36),
                  onPressed: () => provider.playPrevious(),
                ),
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: IconButton(
                    icon: Icon(
                      (isVid && provider.videoController != null && provider.videoController!.value.isPlaying) ||
                          (!isVid && provider.audioPlayer.playing)
                          ? Icons.pause
                          : Icons.play_arrow,
                      color: Colors.black,
                      size: 36,
                    ),
                    onPressed: () => provider.togglePlayPause(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white, size: 36),
                  onPressed: () => provider.playNext(),
                ),
                isVid
                    ? const SizedBox(width: 48)
                    : StreamBuilder<LoopMode>(
                  stream: provider.audioPlayer.loopModeStream,
                  builder: (context, loopSnapshot) {
                    final loopMode = loopSnapshot.data ?? LoopMode.off;
                    const icons = [
                      Icon(Icons.repeat_outlined, color: Colors.white),
                      Icon(Icons.repeat, color: Colors.redAccent),
                      Icon(Icons.repeat_one, color: Colors.redAccent),
                    ];
                    const cycleModes = [
                      LoopMode.off,
                      LoopMode.all,
                      LoopMode.one,
                    ];
                    final index = cycleModes.indexOf(loopMode);
                    return IconButton(
                      icon: icons[index < 0 ? 0 : index],
                      onPressed: () {
                        final nextMode =
                        cycleModes[(cycleModes.indexOf(loopMode) + 1) % cycleModes.length];
                        provider.audioPlayer.setLoopMode(nextMode);
                      },
                    );
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}