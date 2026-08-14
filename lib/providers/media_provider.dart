import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:audio_session/audio_session.dart';
import '../models/media_item.dart';

class MediaProvider with ChangeNotifier, WidgetsBindingObserver {
  final AudioPlayer audioPlayer = AudioPlayer();
  List<MediaItemModel> allFiles = [];
  Map<String, List<MediaItemModel>> foldersMap = {};
  bool isLoading = true;
  bool showAlbumsView = false;
  String? selectedFolder;

  MediaItemModel? currentPlaying;
  List<MediaItemModel> currentPlaylist = [];
  int currentIndex = 0;

  VideoPlayerController? videoController;
  bool isVideoInitializing = false;
  bool isShuffle = false;
  bool isVideoLooping = false;

  bool _isInBackground = false;
  bool _isLifecycleTransitioning = false;
  bool _isInternalStateChange = false;
  bool _isResumingFromBackground = false;

  MediaProvider() {
    WidgetsBinding.instance.addObserver(this);
    _initAudioSession();
    _initPlayerListeners();
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await session.setActive(true);
  }

  void _initPlayerListeners() {
    audioPlayer.playerStateStream.listen((state) {
      notifyListeners();
      if (state.processingState == ProcessingState.completed) {
        playNext();
      }
    });

    audioPlayer.playingStream.listen((audioPlaying) {
      if (_isInternalStateChange || _isResumingFromBackground) return;
      if (currentPlaying != null && currentPlaying!.isVideo && !_isInBackground) {
        final videoPlaying = videoController != null && videoController!.value.isPlaying;
        if (audioPlaying != videoPlaying) {
          if (audioPlaying) {
            playAll();
          } else {
            pauseAll();
          }
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (_isLifecycleTransitioning) return;
    _isLifecycleTransitioning = true;

    try {
      if (currentPlaying != null && currentPlaying!.isVideo) {
        if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
          _isInBackground = true;
          if (videoController != null && videoController!.value.isInitialized) {
            final currentPos = videoController!.value.position;
            await videoController!.pause();
            await _disposeVideoController();
            await audioPlayer.setVolume(1.0);
            await _syncBackgroundAudioSource(currentPlaying!.path, initialPosition: currentPos, playImmediately: true);
            notifyListeners();
          }
        } else if (state == AppLifecycleState.resumed) {
          _isResumingFromBackground = true;
          _isInBackground = false;
          final backgroundAudioPos = audioPlayer.position;
          _isInternalStateChange = true;
          await audioPlayer.pause();
          await audioPlayer.setVolume(0.0);
          _isInternalStateChange = false;

          await setupVideoController(currentPlaying!.path, startPosition: backgroundAudioPos);

          // Stabilize resume window to prevent race conditions
          await Future.delayed(const Duration(milliseconds: 600));
          _isResumingFromBackground = false;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("Lifecycle transition error: $e");
      _isResumingFromBackground = false;
    } finally {
      _isLifecycleTransitioning = false;
    }
  }

  Future<void> _disposeVideoController() async {
    final oldController = videoController;
    videoController = null;
    if (oldController != null) {
      try {
        await oldController.pause();
        await oldController.dispose();
      } catch (e) {
        debugPrint("Error disposing video controller: $e");
      }
    }
  }

  Future<void> setupVideoController(String path, {Duration? startPosition}) async {
    await _disposeVideoController();

    isVideoInitializing = true;
    notifyListeners();

    try {
      final file = File(path);
      if (!await file.exists()) {
        throw Exception("File does not exist: $path");
      }

      final targetPos = startPosition ?? Duration.zero;

      await _syncBackgroundAudioSource(path, initialPosition: targetPos, playImmediately: false);
      await audioPlayer.setVolume(0.0);

      final controller = VideoPlayerController.file(file);
      videoController = controller;

      await controller.initialize().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw TimeoutException("Video initialization timed out");
        },
      );

      await controller.setVolume(1.0);
      await controller.setLooping(isVideoLooping);

      if (targetPos > Duration.zero && targetPos < controller.value.duration) {
        await controller.seekTo(targetPos);
        await Future.delayed(const Duration(milliseconds: 50));
      }

      controller.addListener(() {
        notifyListeners();
        if (controller.value.position >= controller.value.duration &&
            controller.value.duration > Duration.zero &&
            !controller.value.isPlaying) {
          if (isVideoLooping) {
            controller.seekTo(Duration.zero);
            controller.play();
          } else {
            playNext();
          }
        }
      });

      isVideoInitializing = false;
      notifyListeners();

      await controller.play();
      _isInternalStateChange = true;
      await audioPlayer.play();
      _isInternalStateChange = false;
    } catch (e) {
      debugPrint("Video initialization error: $e");
      videoController = null;
      isVideoInitializing = false;
      notifyListeners();
    }
  }

  Future<void> _syncBackgroundAudioSource(String path, {Duration? initialPosition, bool playImmediately = false}) async {
    try {
      final item = allFiles.firstWhere((f) => f.path == path, orElse: () => currentPlaying!);
      final source = AudioSource.uri(
        Uri.file(item.path),
        tag: MediaItem(
          id: item.path,
          title: item.title,
          album: item.folderName,
        ),
      );
      await audioPlayer.setAudioSource(source, initialPosition: initialPosition);
      if (playImmediately) {
        _isInternalStateChange = true;
        await audioPlayer.play();
        _isInternalStateChange = false;
      }
    } catch (e) {
      debugPrint("Sync background audio error: $e");
    }
  }

  Future<void> togglePlayPause() async {
    final isPlaying = (currentPlaying != null && currentPlaying!.isVideo && !_isInBackground)
        ? (videoController != null && videoController!.value.isPlaying)
        : audioPlayer.playing;

    if (isPlaying) {
      await pauseAll();
    } else {
      await playAll();
    }
  }

  Future<void> playAll() async {
    _isInternalStateChange = true;
    try {
      if (currentPlaying != null && currentPlaying!.isVideo && !_isInBackground) {
        if (videoController != null && videoController!.value.isInitialized) {
          await videoController!.setVolume(1.0);
          await videoController!.play();
          await audioPlayer.play();
        } else {
          await setupVideoController(currentPlaying!.path);
          _isInternalStateChange = false;
          return;
        }
      } else {
        await audioPlayer.play();
      }
    } catch (e) {
      debugPrint("playAll error: $e");
    } finally {
      _isInternalStateChange = false;
    }
    notifyListeners();
  }

  Future<void> pauseAll() async {
    _isInternalStateChange = true;
    try {
      if (currentPlaying != null && currentPlaying!.isVideo && !_isInBackground) {
        if (videoController != null && videoController!.value.isInitialized) {
          await videoController!.pause();
          await audioPlayer.pause();
        }
      } else {
        await audioPlayer.pause();
      }
    } catch (e) {
      debugPrint("pauseAll error: $e");
    } finally {
      _isInternalStateChange = false;
    }
    notifyListeners();
  }

  void toggleVideoLoop() {
    isVideoLooping = !isVideoLooping;
    if (videoController != null) {
      videoController!.setLooping(isVideoLooping);
    }
    notifyListeners();
  }

  Future<void> requestPermissionAndScan() async {
    isLoading = true;
    notifyListeners();

    await [
      Permission.storage,
      Permission.manageExternalStorage,
      Permission.audio,
      Permission.videos,
    ].request();

    await scanStorage();
  }

  Future<void> scanStorage() async {
    List<MediaItemModel> found = [];
    Map<String, List<MediaItemModel>> folders = {};

    List<String> targetPaths = ['/storage/emulated/0'];

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

    allFiles = found;
    foldersMap = folders;
    isLoading = false;
    notifyListeners();
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
    } catch (e) {
      debugPrint("Scan directory error: $e");
    }
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

  Future<void> playPlaylist(List<MediaItemModel> list, int initialIndex) async {
    if (list.isEmpty) return;
    currentPlaylist = list;
    currentIndex = initialIndex.clamp(0, list.length - 1);
    final item = list[currentIndex];
    currentPlaying = item;

    if (item.isVideo) {
      notifyListeners();
      await setupVideoController(item.path);
      return;
    }

    await _disposeVideoController();
    await audioPlayer.setVolume(1.0);
    List<AudioSource> sources = list.where((f) => !f.isVideo).map((mediaItem) {
      return AudioSource.uri(
        Uri.file(mediaItem.path),
        tag: MediaItem(
          id: mediaItem.path,
          title: mediaItem.title,
          album: mediaItem.folderName,
        ),
      );
    }).toList();

    try {
      int audioIndex = list.where((f) => !f.isVideo).toList().indexWhere((f) => f.path == item.path);
      if (audioIndex < 0) audioIndex = 0;

      await audioPlayer.setAudioSource(
        ConcatenatingAudioSource(useLazyPreparation: false, children: sources),
        initialIndex: audioIndex,
      );
      await playAll();
      notifyListeners();
    } catch (e) {
      debugPrint("Playback error: $e");
    }
  }

  Future<void> playNext() async {
    if (currentPlaylist.isEmpty) return;
    currentIndex = (currentIndex + 1) % currentPlaylist.length;
    await playPlaylist(currentPlaylist, currentIndex);
  }

  Future<void> playPrevious() async {
    if (currentPlaylist.isEmpty) return;
    currentIndex = (currentIndex - 1 < 0) ? currentPlaylist.length - 1 : currentIndex - 1;
    await playPlaylist(currentPlaylist, currentIndex);
  }

  void toggleShuffle() {
    isShuffle = !isShuffle;
    audioPlayer.setShuffleModeEnabled(isShuffle);
    notifyListeners();
  }

  void setFolder(String? folder) {
    selectedFolder = folder;
    notifyListeners();
  }

  void setAlbumsView(bool value) {
    showAlbumsView = value;
    selectedFolder = null;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeVideoController();
    audioPlayer.dispose();
    super.dispose();
  }
}