import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'audio_manager.dart';

void main() {
  runApp(const MusicApp());
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LibraryScreen(),
    );
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _hasPermission = false;
  List<SongModel>? _selectedSongs;
  List<SongModel> _librarySongs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    requestPermission();
  }

  void requestPermission() async {
    // Yêu cầu quyền và kiểm tra kết quả
    final status = await Permission.storage.request();
    final audioStatus = await Permission.audio.request(); // Cho Android 13+

    if (status.isGranted || audioStatus.isGranted) {
      final songs = await AudioManager().getSongs();
      setState(() {
        _hasPermission = true;
        _librarySongs = songs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Mở trình chọn file
          FilePickerResult? result = await FilePicker.platform.pickFiles(
            type: FileType.audio, // Chỉ chọn file âm thanh
            allowMultiple: true, // Cho phép chọn nhiều file
          );

          if (result != null) {
            // Lấy danh sách đường dẫn và phát nhạc
            List<String> paths = result.paths.whereType<String>().toList();
            debugPrint(
              "Đang phát các file: $paths",
            ); // Kiểm tra log xem có đường dẫn không
            final songs = paths.map((path) {
              final fileName = path.split(RegExp(r'[/\\]')).last;
              return SongModel({
                "_id": path.hashCode,
                "_data": path,
                "title": fileName,
                "artist": "Tệp tùy chọn",
              });
            }).toList();

            setState(() {
              _selectedSongs = songs;
            });
            AudioManager().playSong(songs, 0);
          }
        },
        child: const Icon(Icons.add),
      ),
      appBar: AppBar(
        title: const Text('Thư viện nhạc'),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.search), onPressed: () {})],
      ),
      body: !_hasPermission
          ? const Center(child: Text("Vui lòng cấp quyền truy cập để tải nhạc"))
          : _selectedSongs != null
          ? _buildSongList(_selectedSongs!, isCustomFile: true)
          : _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _librarySongs.isEmpty
          ? const Center(child: Text("Không tìm thấy bài hát nào"))
          : _buildSongList(_librarySongs),
      bottomNavigationBar: const MiniPlayer(),
    );
  }

  void _deleteSong(SongModel song, bool isCustomFile) {
    setState(() {
      if (isCustomFile) {
        _selectedSongs?.remove(song);
        if (_selectedSongs?.isEmpty ?? false) {
          _selectedSongs = null; // Quay về danh sách thư viện nếu xóa hết
        }
      } else {
        _librarySongs.remove(song);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Đã ẩn bài hát khỏi danh sách")),
    );
  }

  Widget _buildSongList(List<SongModel> songs, {bool isCustomFile = false}) {
    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return ListTile(
          leading: isCustomFile
              ? Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.music_note, color: Colors.white),
                )
              : QueryArtworkWidget(
                  id: song.id,
                  type: ArtworkType.AUDIO,
                  nullArtworkWidget: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.music_note, color: Colors.white),
                  ),
                ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(song.artist ?? "Unknown", maxLines: 1),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Xác nhận xóa"),
                    content: Text(
                      "Bạn có chắc muốn xóa bài hát '${song.title}'?",
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Hủy"),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteSong(song, isCustomFile);
                        },
                        child: const Text(
                          "Xóa",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text("Xóa"),
                  ],
                ),
              ),
            ],
          ),
          onTap: () {
            AudioManager().playSong(songs, index);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PlayerScreen()),
            );
          },
        );
      },
    );
  }
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = AudioManager().player;
    return StreamBuilder<SequenceState?>(
      stream: player.sequenceStateStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state?.currentSource == null) return const SizedBox.shrink();
        final song = state!.currentSource!.tag as SongModel;
        final isCustom = song.artist == "Tệp tùy chọn";

        return Container(
          height: 70,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: const Border(top: BorderSide(color: Colors.white10)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              isCustom
                  ? const Icon(Icons.music_note, size: 40)
                  : QueryArtworkWidget(
                      id: song.id,
                      type: ArtworkType.AUDIO,
                      nullArtworkWidget: const Icon(Icons.album, size: 40),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      song.artist ?? "Unknown",
                      maxLines: 1,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              StreamBuilder<PlayerState>(
                stream: player.playerStateStream,
                builder: (context, snapshot) {
                  final playerState = snapshot.data;
                  final processingState = playerState?.processingState;
                  final playing = playerState?.playing;
                  if (processingState == ProcessingState.loading ||
                      processingState == ProcessingState.buffering) {
                    return const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(),
                    );
                  } else if (playing != true) {
                    return IconButton(
                      icon: const Icon(Icons.play_arrow),
                      onPressed: player.play,
                    );
                  } else {
                    return IconButton(
                      icon: const Icon(Icons.pause),
                      onPressed: player.pause,
                    );
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: player.seekToNext,
              ),
            ],
          ),
        );
      },
    );
  }
}

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = AudioManager().player;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<SequenceState?>(
        stream: player.sequenceStateStream,
        builder: (context, snapshot) {
          final state = snapshot.data;
          if (state?.currentSource == null) return const SizedBox.shrink();
          final song = state!.currentSource!.tag as SongModel;
          final isCustom = song.artist == "Tệp tùy chọn";
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Center(
                      child: isCustom
                          ? const Icon(
                              Icons.music_note,
                              size: 120,
                              color: Colors.white54,
                            )
                          : QueryArtworkWidget(
                              id: song.id,
                              type: ArtworkType.AUDIO,
                              artworkHeight: 300,
                              artworkWidth: 300,
                              nullArtworkWidget: const Icon(
                                Icons.music_note,
                                size: 120,
                                color: Colors.white54,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  song.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  song.artist ?? "Unknown",
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 40),
                StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final duration = player.duration ?? Duration.zero;
                    return Column(
                      children: [
                        LinearProgressIndicator(
                          value: duration.inMilliseconds > 0
                              ? position.inMilliseconds /
                                    duration.inMilliseconds
                              : 0.0,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(position)),
                            Text(_formatDuration(duration)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.shuffle),
                      onPressed: () {},
                    ), // Cần thêm logic shuffle
                    IconButton(
                      icon: const Icon(Icons.skip_previous, size: 40),
                      onPressed: player.seekToPrevious,
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: StreamBuilder<PlayerState>(
                        stream: player.playerStateStream,
                        builder: (context, snapshot) {
                          final playing = snapshot.data?.playing ?? false;
                          return IconButton(
                            icon: Icon(
                              playing ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                            ),
                            iconSize: 40,
                            onPressed: playing ? player.pause : player.play,
                          );
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, size: 40),
                      onPressed: player.seekToNext,
                    ),
                    IconButton(
                      icon: const Icon(Icons.repeat),
                      onPressed: () {},
                    ), // Cần thêm logic repeat
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }
}
