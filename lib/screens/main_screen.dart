import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/media_provider.dart';
import '../models/media_item.dart';
import 'full_player_screen.dart';

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mediaProvider = Provider.of<MediaProvider>(context);
    List<MediaItemModel> currentList = mediaProvider.selectedFolder != null
        ? (mediaProvider.foldersMap[mediaProvider.selectedFolder] ?? [])
        : mediaProvider.allFiles;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          mediaProvider.selectedFolder ?? (mediaProvider.showAlbumsView ? 'Альбомы / Папки' : 'Библиотека'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        leading: mediaProvider.selectedFolder != null
            ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Provider.of<MediaProvider>(context, listen: false).setFolder(null),
        )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => Provider.of<MediaProvider>(context, listen: false).requestPermissionAndScan(),
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
                    selected: !mediaProvider.showAlbumsView && mediaProvider.selectedFolder == null,
                    onSelected: (_) => Provider.of<MediaProvider>(context, listen: false).setAlbumsView(false),
                    selectedColor: Colors.white,
                    labelStyle: TextStyle(
                      color: (!mediaProvider.showAlbumsView && mediaProvider.selectedFolder == null)
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
                    selected: mediaProvider.showAlbumsView || mediaProvider.selectedFolder != null,
                    onSelected: (_) => Provider.of<MediaProvider>(context, listen: false).setAlbumsView(true),
                    selectedColor: Colors.white,
                    labelStyle: TextStyle(
                      color: (mediaProvider.showAlbumsView || mediaProvider.selectedFolder != null)
                          ? Colors.black
                          : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (mediaProvider.selectedFolder != null) _buildFolderHeader(context, currentList),
          Expanded(
            child: mediaProvider.isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                : mediaProvider.showAlbumsView && mediaProvider.selectedFolder == null
                ? _buildFolderList(context)
                : _buildFileList(context, currentList),
          ),
          if (mediaProvider.currentPlaying != null) _buildMiniPlayer(context),
        ],
      ),
    );
  }

  Widget _buildFolderHeader(BuildContext context, List<MediaItemModel> folderFiles) {
    final mediaProvider = Provider.of<MediaProvider>(context, listen: false);
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
                  Provider.of<MediaProvider>(context).selectedFolder ?? '',
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
                      onPressed: folderFiles.isEmpty ? null : () => mediaProvider.playPlaylist(folderFiles, 0),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Включить'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.shuffle),
                      onPressed: folderFiles.isEmpty
                          ? null
                          : () {
                        mediaProvider.toggleShuffle();
                        mediaProvider.playPlaylist(folderFiles, 0);
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

  Widget _buildFolderList(BuildContext context) {
    final mediaProvider = Provider.of<MediaProvider>(context);
    final keys = mediaProvider.foldersMap.keys.toList();
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
                onPressed: () => Provider.of<MediaProvider>(context, listen: false).requestPermissionAndScan(),
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
        int count = mediaProvider.foldersMap[folder]?.length ?? 0;
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
              color: Colors.white70,
            ),
          ),
          title: Text(folder, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('$count файлов', style: const TextStyle(color: Colors.grey)),
          onTap: () => Provider.of<MediaProvider>(context, listen: false).setFolder(folder),
        );
      },
    );
  }

  Widget _buildFileList(BuildContext context, List<MediaItemModel> list) {
    final mediaProvider = Provider.of<MediaProvider>(context);
    if (list.isEmpty) {
      return const Center(
        child: Text('Нет медиафайлов', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        MediaItemModel item = list[index];
        bool isPlayingCurrent = mediaProvider.currentPlaying?.path == item.path;

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
          onTap: () => Provider.of<MediaProvider>(context, listen: false).playPlaylist(list, index),
        );
      },
    );
  }

  Widget _buildMiniPlayer(BuildContext context) {
    final mediaProvider = Provider.of<MediaProvider>(context);
    bool isVid = mediaProvider.currentPlaying?.isVideo ?? false;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FullPlayerScreen()),
        );
      },
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
              child: isVid && mediaProvider.videoController != null && mediaProvider.videoController!.value.isInitialized
                  ? FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: mediaProvider.videoController!.value.size.width,
                  height: mediaProvider.videoController!.value.size.height,
                  child: VideoPlayer(mediaProvider.videoController!),
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
                    mediaProvider.currentPlaying?.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    mediaProvider.currentPlaying?.folderName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.skip_previous, color: Colors.white),
              onPressed: () => Provider.of<MediaProvider>(context, listen: false).playPrevious(),
            ),
            StreamBuilder<PlayerState>(
              stream: mediaProvider.audioPlayer.playerStateStream,
              builder: (context, snapshot) {
                final playerState = snapshot.data;
                final playing = playerState?.playing ?? false;
                return IconButton(
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
                  onPressed: () => Provider.of<MediaProvider>(context, listen: false).togglePlayPause(),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.skip_next, color: Colors.white),
              onPressed: () => Provider.of<MediaProvider>(context, listen: false).playNext(),
            ),
          ],
        ),
      ),
    );
  }
}