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
      setState(() {
        _hasPermission = true;
        _librarySongs = [];
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
              String directory = path;
              final lastSeparator = path.lastIndexOf(RegExp(r'[/\\]'));
              if (lastSeparator != -1) {
                directory = path.substring(0, lastSeparator);
              }
              return SongModel({
                "_id": path.hashCode,
                "_data": path,
                "title": fileName,
                "artist": directory,
                "genre": "CustomFile",
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
          ? const Center(child: Text("Nhấn nút + để thêm bài hát"))
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
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 24,
              color: Colors.cyan,
            ),
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
        final isCustom = song.genre == "CustomFile";

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PlayerScreen()),
            );
          },
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: const Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        isCustom
                            ? const Icon(Icons.music_note, size: 40)
                            : QueryArtworkWidget(
                                id: song.id,
                                type: ArtworkType.AUDIO,
                                nullArtworkWidget: const Icon(
                                  Icons.album,
                                  size: 40,
                                ),
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 24,
                                  color: Colors.cyan,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_previous),
                          onPressed: player.seekToPrevious,
                        ),
                        StreamBuilder<PlayerState>(
                          stream: player.playerStateStream,
                          builder: (context, snapshot) {
                            final playerState = snapshot.data;
                            final processingState =
                                playerState?.processingState;
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
                  ),
                ),
                StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final duration = player.duration ?? Duration.zero;
                    double value = 0.0;
                    if (duration.inMilliseconds > 0) {
                      value = position.inMilliseconds / duration.inMilliseconds;
                      value = value.clamp(0.0, 1.0);
                    }
                    return LinearProgressIndicator(
                      value: value,
                      minHeight: 2.0,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    );
                  },
                ),
              ],
            ),
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
      extendBodyBehindAppBar: true, // Để background tràn lên status bar
      appBar: AppBar(
        title: const Text('Đang phát'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
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
          final isCustom = song.genre == "CustomFile";

          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.deepPurple.shade900, Colors.black],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 100, 24, 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
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
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isCustom) ...[
                    const SizedBox(height: 8),
                    Text(
                      song.artist ?? "Unknown",
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 30),
                  // Thanh trượt thời gian (Seek Bar)
                  StreamBuilder<Duration>(
                    stream: player.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final duration = player.duration ?? Duration.zero;
                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6.0,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14.0,
                              ),
                              trackHeight: 4.0,
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              min: 0,
                              max: duration.inMilliseconds.toDouble(),
                              value: position.inMilliseconds.toDouble().clamp(
                                0,
                                duration.inMilliseconds.toDouble(),
                              ),
                              onChanged: (value) {
                                player.seek(
                                  Duration(milliseconds: value.toInt()),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(position),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                Text(
                                  _formatDuration(duration),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  // Các nút điều khiển
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Nút Shuffle (Ngẫu nhiên)
                      StreamBuilder<bool>(
                        stream: player.shuffleModeEnabledStream,
                        builder: (context, snapshot) {
                          final shuffleModeEnabled = snapshot.data ?? false;
                          return IconButton(
                            icon: const Icon(Icons.shuffle),
                            color: shuffleModeEnabled
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white70,
                            onPressed: () async {
                              final enable = !shuffleModeEnabled;
                              if (enable) {
                                await player.shuffle();
                              }
                              await player.setShuffleModeEnabled(enable);
                            },
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.skip_previous,
                          size: 40,
                          color: Colors.white,
                        ),
                        onPressed: player.seekToPrevious,
                      ),
                      // Nút Play/Pause lớn
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.2),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: StreamBuilder<PlayerState>(
                          stream: player.playerStateStream,
                          builder: (context, snapshot) {
                            final playing = snapshot.data?.playing ?? false;
                            return IconButton(
                              icon: Icon(
                                playing ? Icons.pause : Icons.play_arrow,
                                color: Colors.black,
                              ),
                              iconSize: 40,
                              onPressed: playing ? player.pause : player.play,
                            );
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.skip_next,
                          size: 40,
                          color: Colors.white,
                        ),
                        onPressed: player.seekToNext,
                      ),
                      // Nút Repeat (Lặp lại)
                      StreamBuilder<LoopMode>(
                        stream: player.loopModeStream,
                        builder: (context, snapshot) {
                          final loopMode = snapshot.data ?? LoopMode.off;
                          const icons = [
                            Icon(Icons.repeat, color: Colors.white70),
                            Icon(Icons.repeat, color: Colors.deepPurpleAccent),
                            Icon(
                              Icons.repeat_one,
                              color: Colors.deepPurpleAccent,
                            ),
                          ];
                          const cycleModes = [
                            LoopMode.off,
                            LoopMode.all,
                            LoopMode.one,
                          ];
                          final index = cycleModes.indexOf(loopMode);
                          return IconButton(
                            icon: icons[index],
                            onPressed: () {
                              player.setLoopMode(
                                cycleModes[(cycleModes.indexOf(loopMode) + 1) %
                                    cycleModes.length],
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
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
