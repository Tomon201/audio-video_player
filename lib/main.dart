import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.ytmusic.channel.audio',
    androidNotificationChannelName: 'YT Music Player',
    androidNotificationOngoing: true,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YT Music Offline',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.redAccent,
          surface: Color(0xFF212121),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MediaItemModel {
  final String path;
  final String title;
  final String folderName;
  final bool isVideo;

  MediaItemModel({
    required this.path,
    required this.title,
    required this.folderName,
    required this.isVideo,
  });
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<MediaItemModel> _allFiles = [];
  Map<String, List<MediaItemModel>> _foldersMap = {};
  bool _isLoading = true;
  bool _showAlbumsView = false;
  String? _selectedFolder;

  MediaItemModel? _currentPlaying;
  VideoPlayerController? _videoController;
  bool _isVideoInitializing = false;
  bool _isShuffle = false;

  @override
  void initState() {
    super.initState();
    _requestPermissionAndScan();
    _listenSequenceState();
  }

  void _listenSequenceState() {
    _audioPlayer.sequenceStateStream.listen((sequenceState) {
      if (sequenceState == null) return;
      final currentItem = sequenceState.currentSource;
      if (currentItem != null && currentItem is UriAudioSource) {
        final tag = currentItem.tag;
        if (tag is MediaItem) {
          final matching = _allFiles.firstWhere(
                (f) => f.path == tag.id,
            orElse: () => MediaItemModel(
              path: tag.id,
              title: tag.title,
              folderName: tag.album ?? 'Музыка',
              isVideo: false,
            ),
          );

          if (_currentPlaying?.path != matching.path) {
            setState(() {
              _currentPlaying = matching;
            });
            _disposeVideoController();
          }
        }
      }
    });
  }

  Future<void> _disposeVideoController() async {
    final oldController = _videoController;
    _videoController = null;
    if (oldController != null) {
      try {
        await oldController.pause();
        await oldController.dispose();
      } catch (_) {}
    }
  }

  Future<void> _setupVideoController(String path) async {
    if (!mounted) return;
    await _disposeVideoController();

    setState(() {
      _isVideoInitializing = true;
    });

    try {
      final file = File(path);
      if (!await file.exists()) {
        throw Exception("File does not exist: $path");
      }

      final controller = VideoPlayerController.file(file);
      _videoController = controller;

      await controller.initialize();
      await controller.setVolume(1.0);
      await controller.setLooping(false);
      await controller.play();

      if (mounted) {
        setState(() {
          _isVideoInitializing = false;
        });
      }
    } catch (e) {
      debugPrint("Video initialization error: $e");
      if (mounted) {
        setState(() {
          _videoController = null;
          _isVideoInitializing = false;
        });
      }
    }
  }

  Future<void> _requestPermissionAndScan() async {
    setState(() => _isLoading = true);

    await [
      Permission.storage,
      Permission.manageExternalStorage,
      Permission.audio,
      Permission.videos,
    ].request();

    await _scanStorage();
  }

  Future<void> _scanStorage() async {
    List<MediaItemModel> found = [];
    Map<String, List<MediaItemModel>> folders = {};

    List<String> targetPaths = [
      '/storage/emulated/0',
    ];

    for (String path in targetPaths) {
      Directory dir = Directory(path);
      if (await dir.exists()) {
        try {
          await _scanDirectoryRecursive(dir, found, folders, isRootScan: true);
        } catch (e) {
          debugPrint("Error scanning path $path: $e");
        }
      }
    }

    if (mounted) {
      setState(() {
        _allFiles = found;
        _foldersMap = folders;
        _isLoading = false;
      });
    }
  }

  Future<void> _scanDirectoryRecursive(
      Directory dir,
      List<MediaItemModel> found,
      Map<String, List<MediaItemModel>> folders,
      {bool isRootScan = false}
      ) async {
    try {
      final List<FileSystemEntity> entities = dir.listSync(followLinks: false);
      for (var entity in entities) {
        String name = entity.path.toLowerCase();

        if (name.contains('whatsapp') || name.contains('/android/data') || name.contains('/android/obb')) {
          continue;
        }

        if (entity is File) {
          _processFile(entity, found, folders, isRootFile: isRootScan);
        } else if (entity is Directory) {
          String folderNameOnly = entity.path.split('/').last.toLowerCase();
          if (!folderNameOnly.startsWith('.')) {
            await _scanDirectoryRecursive(entity, found, folders, isRootScan: false);
          }
        }
      }
    } catch (_) {}
  }

  void _processFile(
      File entity,
      List<MediaItemModel> found,
      Map<String, List<MediaItemModel>> folders,
      {required bool isRootFile}
      ) {
    String p = entity.path.toLowerCase();
    if (p.contains('whatsapp')) return;

    if (p.endsWith('.mp3') || p.endsWith('.mp4') || p.endsWith('.m4a') ||
        p.endsWith('.wav') || p.endsWith('.m4v') || p.endsWith('.mkv') ||
        p.endsWith('.flac') || p.endsWith('.aac') || p.endsWith('.ogg')) {

      List<String> parts = entity.path.split('/');
      String fileName = parts.isNotEmpty ? parts.last : entity.path;

      String folderName;
      if (isRootFile || parts.length <= 5) {
        folderName = '📁 Внутренняя память (Корень)';
      } else {
        folderName = parts[parts.length - 2];
      }

      bool isVid = p.endsWith('.mp4') || p.endsWith('.m4v') || p.endsWith('.mkv');

      MediaItemModel item = MediaItemModel(
        path: entity.path,
        title: fileName,
        folderName: folderName,
        isVideo: isVid,
      );

      found.add(item);
      folders.putIfAbsent(folderName, () => []).add(item);
    }
  }

  Future<void> _playPlaylist(List<MediaItemModel> list, int initialIndex) async {
    final item = list[initialIndex];
    if (item.isVideo) {
      setState(() {
        _currentPlaying = item;
      });
      await _audioPlayer.pause();
      await _setupVideoController(item.path);
      return;
    }

    await _disposeVideoController();
    List<AudioSource> sources = list.where((f) => !f.isVideo).map((mediaItem) {
      return AudioSource.uri(
        Uri.file(mediaItem.path),
        tag: MediaItem(
          id: mediaItem.path,
          album: mediaItem.folderName,
          title: mediaItem.title,
          artist: 'Папка: ${mediaItem.folderName}',
        ),
      );
    }).toList();

    try {
      int audioIndex = sources.indexWhere((s) {
        if (s is UriAudioSource) {
          final tag = s.tag;
          if (tag is MediaItem) return tag.id == item.path;
        }
        return false;
      });
      if (audioIndex < 0) audioIndex = 0;

      await _audioPlayer.setAudioSource(
        ConcatenatingAudioSource(
          useLazyPreparation: false,
          children: sources,
        ),
        initialIndex: audioIndex,
      );
      _audioPlayer.play();
    } catch (e) {
      debugPrint("Playback error: $e");
    }
  }

  void _toggleShuffle() {
    setState(() {
      _isShuffle = !_isShuffle;
    });
    _audioPlayer.setShuffleModeEnabled(_isShuffle);
  }

  @override
  void dispose() {
    _disposeVideoController();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<MediaItemModel> currentList = _selectedFolder != null
        ? (_foldersMap[_selectedFolder] ?? [])
        : _allFiles;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          _selectedFolder ?? (_showAlbumsView ? 'Альбомы / Папки' : 'Библиотека'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        leading: _selectedFolder != null
            ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _selectedFolder = null),
        )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _requestPermissionAndScan,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Все файлы', overflow: TextOverflow.ellipsis),
                    selected: !_showAlbumsView && _selectedFolder == null,
                    onSelected: (_) {
                      setState(() {
                        _showAlbumsView = false;
                        _selectedFolder = null;
                      });
                    },
                    selectedColor: Colors.white,
                    labelStyle: TextStyle(
                      color: (!_showAlbumsView && _selectedFolder == null)
                          ? Colors.black
                          : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Папки', overflow: TextOverflow.ellipsis),
                    selected: _showAlbumsView || _selectedFolder != null,
                    onSelected: (_) {
                      setState(() {
                        _showAlbumsView = true;
                        _selectedFolder = null;
                      });
                    },
                    selectedColor: Colors.white,
                    labelStyle: TextStyle(
                      color: (_showAlbumsView || _selectedFolder != null)
                          ? Colors.black
                          : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_selectedFolder != null) _buildFolderHeader(currentList),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                : _showAlbumsView && _selectedFolder == null
                ? _buildFolderList()
                : _buildFileList(currentList),
          ),
          if (_currentPlaying != null) _buildMiniPlayer(),
        ],
      ),
    );
  }

  Widget _buildFolderHeader(List<MediaItemModel> folderFiles) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.folder, size: 40, color: Colors.white54),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedFolder ?? '',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${folderFiles.length} файлов',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: folderFiles.isEmpty
                          ? null
                          : () => _playPlaylist(folderFiles, 0),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Включить'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.shuffle),
                      onPressed: folderFiles.isEmpty
                          ? null
                          : () {
                        _toggleShuffle();
                        _playPlaylist(folderFiles, 0);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderList() {
    final keys = _foldersMap.keys.toList();
    if (keys.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Папки не найдены',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Убедитесь, что даны разрешения на доступ к файлам.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                onPressed: _requestPermissionAndScan,
                child: const Text('Сканировать повторно'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (context, index) {
        String folder = keys[index];
        int count = _foldersMap[folder]?.length ?? 0;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
                folder.contains('Корень') ? Icons.sd_storage : Icons.folder_special,
                color: Colors.white70
            ),
          ),
          title: Text(folder, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('$count файлов', style: const TextStyle(color: Colors.grey)),
          onTap: () {
            setState(() {
              _selectedFolder = folder;
            });
          },
        );
      },
    );
  }

  Widget _buildFileList(List<MediaItemModel> list) {
    if (list.isEmpty) {
      return const Center(
        child: Text('Нет медиафайлов', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        MediaItemModel item = list[index];
        bool isPlayingCurrent = _currentPlaying?.path == item.path;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              item.isVideo ? Icons.videocam : Icons.music_note,
              color: isPlayingCurrent ? Colors.redAccent : Colors.white70,
            ),
          ),
          title: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isPlayingCurrent ? FontWeight.bold : FontWeight.normal,
              color: isPlayingCurrent ? Colors.redAccent : Colors.white,
            ),
          ),
          subtitle: Text(
            item.folderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          trailing: isPlayingCurrent
              ? const Icon(Icons.bar_chart, color: Colors.redAccent)
              : null,
          onTap: () => _playPlaylist(list, index),
        );
      },
    );
  }

  void _openFullPlayer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.94,
          minChildSize: 0.5,
          maxChildSize: 0.98,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[700],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    height: 280,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _currentPlaying != null && _currentPlaying!.isVideo
                        ? (_isVideoInitializing
                        ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                        : (_videoController != null && _videoController!.value.isInitialized
                        ? Center(
                      child: AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: VideoPlayer(_videoController!),
                      ),
                    )
                        : const Center(child: Icon(Icons.broken_image, size: 64, color: Colors.grey))))
                        : const Center(
                      child: Icon(Icons.music_note, size: 80, color: Colors.white54),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _currentPlaying?.title ?? '',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _currentPlaying?.folderName ?? '',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_currentPlaying != null && _currentPlaying!.isVideo)
                    _buildVideoControls()
                  else
                    _buildAudioControls(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVideoControls() {
    if (_videoController == null) return const SizedBox();
    return Column(
      children: [
        ValueListenableBuilder(
          valueListenable: _videoController!,
          builder: (context, VideoPlayerValue value, child) {
            final position = value.position;
            final duration = value.duration;
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
                    _videoController!.seekTo(Duration(milliseconds: val.toInt()));
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
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: IconButton(
                icon: Icon(
                  _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.black,
                  size: 36,
                ),
                onPressed: () {
                  setState(() {
                    if (_videoController!.value.isPlaying) {
                      _videoController!.pause();
                    } else {
                      _videoController!.play();
                    }
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAudioControls() {
    return Column(
      children: [
        StreamBuilder<Duration>(
          stream: _audioPlayer.positionStream,
          builder: (context, snapshot) {
            final position = snapshot.data ?? Duration.zero;
            final duration = _audioPlayer.duration ?? Duration.zero;
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
                    _audioPlayer.seek(Duration(milliseconds: val.toInt()));
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
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: Icon(
                _isShuffle ? Icons.shuffle : Icons.shuffle_outlined,
                color: _isShuffle ? Colors.redAccent : Colors.white,
              ),
              onPressed: _toggleShuffle,
            ),
            IconButton(
              icon: const Icon(Icons.skip_previous, size: 36),
              onPressed: () => _audioPlayer.seekToPrevious(),
            ),
            StreamBuilder<PlayerState>(
              stream: _audioPlayer.playerStateStream,
              builder: (context, snapshot) {
                final playing = snapshot.data?.playing ?? false;
                return Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: IconButton(
                    icon: Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.black,
                      size: 36,
                    ),
                    onPressed: () {
                      if (playing) {
                        _audioPlayer.pause();
                      } else {
                        _audioPlayer.play();
                      }
                    },
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.skip_next, size: 36),
              onPressed: () => _audioPlayer.seekToNext(),
            ),
            // Precise 3-state repeat stream builder matching just_audio official example
            StreamBuilder<LoopMode>(
              stream: _audioPlayer.loopModeStream,
              builder: (context, snapshot) {
                final loopMode = snapshot.data ?? LoopMode.off;
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
                    final nextMode = cycleModes[(cycleModes.indexOf(loopMode) + 1) % cycleModes.length];
                    _audioPlayer.setLoopMode(nextMode);
                  },
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniPlayer() {
    bool isVid = _currentPlaying?.isVideo ?? false;
    return GestureDetector(
      onTap: _openFullPlayer,
      child: Container(
        height: 64,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF212121),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: isVid && _videoController != null && _videoController!.value.isInitialized
                  ? FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController!.value.size.width,
                  height: _videoController!.value.size.height,
                  child: VideoPlayer(_videoController!),
                ),
              )
                  : const Icon(Icons.music_note, color: Colors.white70),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentPlaying?.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    _currentPlaying?.folderName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (!isVid) ...[
              IconButton(
                icon: const Icon(Icons.skip_previous, color: Colors.white),
                onPressed: () => _audioPlayer.seekToPrevious(),
              ),
              StreamBuilder<PlayerState>(
                stream: _audioPlayer.playerStateStream,
                builder: (context, snapshot) {
                  final playing = snapshot.data?.playing ?? false;
                  return IconButton(
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
                    onPressed: () {
                      if (playing) {
                        _audioPlayer.pause();
                      } else {
                        _audioPlayer.play();
                      }
                    },
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, color: Colors.white),
                onPressed: () => _audioPlayer.seekToNext(),
              ),
            ] else ...[
              IconButton(
                icon: Icon(
                  _videoController != null && _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: () {
                  setState(() {
                    if (_videoController != null) {
                      if (_videoController!.value.isPlaying) {
                        _videoController!.pause();
                      } else {
                        _videoController!.play();
                      }
                    }
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}