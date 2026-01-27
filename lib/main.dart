import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_manager.dart';

enum LibraryMode { manual, device, folder }

enum FileFilter { all, mp3, mp4 }

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
  List<SongModel> _folderSongs = [];
  bool _isLoading = true;
  LibraryMode _libraryMode = LibraryMode.manual;
  String? _folderPath;
  FileFilter _fileFilter = FileFilter.all;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await _loadSavedData();
    await requestPermission();
  }

  Future<void> requestPermission() async {
    // Yêu cầu quyền và kiểm tra kết quả
    // Xin quyền Storage (Android <13) và Audio/Video (Android 13+)
    Map<Permission, PermissionStatus> statuses = await [
      Permission.storage,
      Permission.audio,
      Permission.videos,
    ].request();

    // Kiểm tra và yêu cầu quyền quản lý bộ nhớ ngoài (Android 11+)
    // Quyền này giúp quét được thư mục Download và sửa lỗi "Android chặn..."
    if (Platform.isAndroid &&
        await Permission.manageExternalStorage.status.isDenied) {
      await Permission.manageExternalStorage.request();
    }

    if (statuses[Permission.storage]!.isGranted ||
        statuses[Permission.audio]!.isGranted ||
        statuses[Permission.videos]!.isGranted ||
        (await Permission.manageExternalStorage.status.isGranted)) {
      setState(() {
        _hasPermission = true;
      });
      if (_libraryMode == LibraryMode.device) {
        await _fetchDeviceSongs();
      } else {
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  // Hàm quét nhạc từ thiết bị (chỉ gọi khi cần)
  Future<void> _fetchDeviceSongs() async {
    setState(() => _isLoading = true);
    final songs = await AudioManager().getSongs();
    setState(() {
      _librarySongs = songs;
      _isLoading = false;
    });
  }

  // Hàm quét nhạc từ thư mục được chọn
  Future<void> _fetchFolderSongs(String path) async {
    setState(() => _isLoading = true);
    try {
      final dir = Directory(path);
      List<FileSystemEntity> entities = [];
      // Quét đệ quy (recursive: true) để tìm cả trong thư mục con
      try {
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          entities.add(entity);
        }
      } catch (e) {
        debugPrint("Lỗi quét file trong thư mục: $e");
      }

      final songs = entities
          .whereType<File>()
          .where((file) {
            final ext = file.path.split('.').last.toLowerCase();
            return [
              'mp3',
              'wav',
              'm4a',
              'flac',
              'ogg',
              'aac',
              'mp4',
            ].contains(ext);
          })
          .map((file) {
            final fileName = file.path.split(RegExp(r'[/\\]')).last;
            final isMp4 = fileName.toLowerCase().endsWith('.mp4');
            return SongModel({
              "_id": file.path.hashCode,
              "_data": file.path,
              "title": fileName,
              "artist": path.split(RegExp(r'[/\\]')).last,
              "genre": isMp4 ? "VideoFile" : "FolderFile",
            });
          })
          .toList();

      setState(() {
        _folderSongs = songs;
        _folderPath = path;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Lỗi đọc thư mục: $e");
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Không thể đọc thư mục này (có thể do quyền hạn chế của Android).",
            ),
          ),
        );
      }
    }
  }

  // Hàm tải dữ liệu đã lưu (chế độ + danh sách nhạc)
  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedModeIndex = prefs.getInt('library_mode');
    final savedFolderPath = prefs.getString('folder_path');
    final List<String>? paths = prefs.getStringList('custom_playlist');

    List<SongModel>? songs;
    if (paths != null && paths.isNotEmpty) {
      songs = paths.map((path) {
        final fileName = path.split(RegExp(r'[/\\]')).last;
        String directory = path;
        final lastSeparator = path.lastIndexOf(RegExp(r'[/\\]'));
        if (lastSeparator != -1) {
          directory = path.substring(0, lastSeparator);
        }
        final isMp4 = path.toLowerCase().endsWith('.mp4');
        return SongModel({
          "_id": path.hashCode,
          "_data": path,
          "title": fileName,
          "artist": directory,
          "genre": isMp4 ? "VideoFile" : "CustomFile",
        });
      }).toList();
    }

    setState(() {
      if (savedModeIndex != null) {
        _libraryMode = LibraryMode.values[savedModeIndex];
      } else {
        // Migration cho phiên bản cũ
        final oldDeviceMode = prefs.getBool('is_device_mode') ?? false;
        _libraryMode = oldDeviceMode ? LibraryMode.device : LibraryMode.manual;
      }
      _folderPath = savedFolderPath;
      _selectedSongs = songs;
    });

    if (_libraryMode == LibraryMode.folder && _folderPath != null) {
      await _fetchFolderSongs(_folderPath!);
    }
  }

  // Hàm lưu danh sách nhạc hiện tại vào bộ nhớ
  Future<void> _saveSelectedSongs() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedSongs != null && _selectedSongs!.isNotEmpty) {
      final paths = _selectedSongs!.map((s) => s.data).toList();
      await prefs.setStringList('custom_playlist', paths);
    } else {
      await prefs.remove('custom_playlist');
    }
  }

  // Hàm lưu chế độ xem hiện tại
  Future<void> _saveMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('library_mode', _libraryMode.index);
    if (_folderPath != null) {
      await prefs.setString('folder_path', _folderPath!);
    }
  }

  List<SongModel> _getFilteredSongs(List<SongModel> songs) {
    if (_fileFilter == FileFilter.all) return songs;
    return songs.where((song) {
      final path = song.data.toLowerCase();
      if (_fileFilter == FileFilter.mp3) return path.endsWith('.mp3');
      if (_fileFilter == FileFilter.mp4) return path.endsWith('.mp4');
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _libraryMode == LibraryMode.manual
          ? FloatingActionButton(
              onPressed: () async {
                // Mở trình chọn file
                FilePickerResult? result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: [
                    'mp3',
                    'wav',
                    'm4a',
                    'flac',
                    'ogg',
                    'aac',
                    'mp4',
                  ],
                  allowMultiple: true, // Cho phép chọn nhiều file
                );

                if (result != null) {
                  // Lấy danh sách đường dẫn và phát nhạc
                  List<String> paths = result.paths
                      .whereType<String>()
                      .toList();
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
                    final isMp4 = path.toLowerCase().endsWith('.mp4');
                    return SongModel({
                      "_id": path.hashCode,
                      "_data": path,
                      "title": fileName,
                      "artist": directory,
                      "genre": isMp4 ? "VideoFile" : "CustomFile",
                    });
                  }).toList();

                  int playIndex = 0;
                  setState(() {
                    // Nối thêm vào danh sách cũ thay vì thay thế
                    if (_selectedSongs != null) {
                      playIndex =
                          _selectedSongs!.length; // Vị trí bắt đầu của bài mới
                      _selectedSongs!.addAll(songs);
                    } else {
                      _selectedSongs = songs;
                    }
                  });
                  _saveSelectedSongs(); // Lưu lại danh sách mới
                  AudioManager().playSong(_selectedSongs!, playIndex);
                }
              },
              child: const Icon(Icons.add),
            )
          : (_libraryMode == LibraryMode.folder
                ? FloatingActionButton(
                    onPressed: () async {
                      try {
                        String? path = await FilePicker.platform
                            .getDirectoryPath(lockParentWindow: true);
                        if (path != null) {
                          _fetchFolderSongs(path);
                          _saveMode();
                        } else {
                          // Người dùng hủy chọn hoặc hệ thống chặn
                          debugPrint("Không chọn được thư mục (path = null)");
                        }
                      } catch (e) {
                        debugPrint("Lỗi chọn thư mục: $e");
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Lỗi mở chọn thư mục: $e")),
                          );
                        }
                      }
                    },
                    tooltip: "Chọn thư mục khác",
                    child: const Icon(Icons.folder_open),
                  )
                : null),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.radar),
          tooltip: "Quét lại",
          onPressed: () {
            if (_libraryMode == LibraryMode.device) {
              _fetchDeviceSongs();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Đang quét lại thiết bị...")),
              );
            } else if (_libraryMode == LibraryMode.folder &&
                _folderPath != null) {
              _fetchFolderSongs(_folderPath!);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Đang cập nhật thư mục...")),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Chế độ thủ công không cần cập nhật"),
                ),
              );
            }
          },
        ),
        title: Text(
          _libraryMode == LibraryMode.device
              ? 'Toàn bộ thiết bị'
              : (_libraryMode == LibraryMode.folder
                    ? (_folderPath != null
                          ? _folderPath!.split(RegExp(r'[/\\]')).last
                          : 'Thư mục')
                    : 'Danh sách thủ công'),
        ),
        centerTitle: true,
        actions: [
          if (_libraryMode != LibraryMode.manual)
            PopupMenuButton<FileFilter>(
              icon: const Icon(Icons.filter_list),
              tooltip: "Lọc định dạng",
              onSelected: (FileFilter result) {
                setState(() {
                  _fileFilter = result;
                });
              },
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<FileFilter>>[
                    const PopupMenuItem<FileFilter>(
                      value: FileFilter.all,
                      child: Text('Tất cả'),
                    ),
                    const PopupMenuItem<FileFilter>(
                      value: FileFilter.mp3,
                      child: Text('Chỉ MP3'),
                    ),
                    const PopupMenuItem<FileFilter>(
                      value: FileFilter.mp4,
                      child: Text('Chỉ MP4'),
                    ),
                  ],
            ),
          PopupMenuButton<LibraryMode>(
            icon: Icon(_getModeIcon()),
            tooltip: "Chuyển chế độ",
            onSelected: (LibraryMode mode) {
              if (_libraryMode != mode) {
                setState(() => _libraryMode = mode);
                if (mode == LibraryMode.device && _librarySongs.isEmpty) {
                  _fetchDeviceSongs();
                } else if (mode == LibraryMode.folder && _folderPath != null) {
                  _fetchFolderSongs(_folderPath!);
                }
                _saveMode();
              }
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<LibraryMode>>[
                  const PopupMenuItem<LibraryMode>(
                    value: LibraryMode.manual,
                    child: Row(
                      children: [
                        Icon(Icons.library_music),
                        SizedBox(width: 8),
                        Text('Danh sách thủ công'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<LibraryMode>(
                    value: LibraryMode.device,
                    child: Row(
                      children: [
                        Icon(Icons.phone_android),
                        SizedBox(width: 8),
                        Text('Toàn bộ thiết bị'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<LibraryMode>(
                    value: LibraryMode.folder,
                    child: Row(
                      children: [
                        Icon(Icons.folder),
                        SizedBox(width: 8),
                        Text('Thư mục'),
                      ],
                    ),
                  ),
                ],
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // Tìm kiếm dựa trên danh sách đang hiển thị
              List<SongModel> currentList = [];
              if (_libraryMode == LibraryMode.device) {
                currentList = _librarySongs;
              } else if (_libraryMode == LibraryMode.folder) {
                currentList = _folderSongs;
              } else {
                currentList = _selectedSongs ?? [];
              }

              if (currentList.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Danh sách nhạc trống")),
                );
                return;
              }

              showSearch(
                context: context,
                delegate: SongSearchDelegate(
                  songs: currentList,
                  isCustomFile: _libraryMode != LibraryMode.device,
                ),
              );
            },
          ),
        ],
      ),
      body: !_hasPermission
          ? const Center(child: Text("Vui lòng cấp quyền truy cập để tải nhạc"))
          : _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _libraryMode == LibraryMode.device
          ? (_librarySongs.isEmpty
                ? const Center(
                    child: Text("Không tìm thấy bài hát nào trên máy"),
                  )
                : _buildSongList(_getFilteredSongs(_librarySongs)))
          : (_libraryMode == LibraryMode.folder
                ? (_folderSongs.isEmpty
                      ? Center(
                          child: Text(
                            _folderPath == null
                                ? "Chưa chọn thư mục. Nhấn nút folder để chọn."
                                : "Thư mục trống",
                          ),
                        )
                      : _buildSongList(
                          _getFilteredSongs(_folderSongs),
                          isCustomFile: true,
                        ))
                : (_selectedSongs == null || _selectedSongs!.isEmpty
                      ? const Center(child: Text("Nhấn nút + để thêm bài hát"))
                      : _buildSongList(_selectedSongs!, isCustomFile: true))),
      bottomNavigationBar: const MiniPlayer(),
    );
  }

  void _deleteSong(SongModel song, bool isCustomFile) {
    setState(() {
      if (isCustomFile) {
        if (_libraryMode == LibraryMode.folder) {
          _folderSongs.remove(song);
        } else {
          _selectedSongs?.remove(song);
          if (_selectedSongs?.isEmpty ?? false) {
            _selectedSongs = null;
          }
          _saveSelectedSongs();
        }
      } else {
        _librarySongs.remove(song);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Đã ẩn bài hát khỏi danh sách")),
    );
  }

  IconData _getModeIcon() {
    switch (_libraryMode) {
      case LibraryMode.manual:
        return Icons.library_music;
      case LibraryMode.device:
        return Icons.phone_android;
      case LibraryMode.folder:
        return Icons.folder;
    }
  }

  void _showSongInfo(SongModel song) async {
    final file = File(song.data);
    String sizeString = "Không xác định";
    String dateString = "Không xác định";

    if (await file.exists()) {
      final stat = await file.stat();
      final sizeMb = stat.size / (1024 * 1024);
      sizeString = "${sizeMb.toStringAsFixed(2)} MB";
      // Định dạng ngày tháng đơn giản (YYYY-MM-DD HH:MM:SS)
      dateString = stat.modified.toString().split('.')[0];
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Thông tin file"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow("Tên file:", song.title),
            const SizedBox(height: 8),
            _buildInfoRow("Kích thước:", sizeString),
            const SizedBox(height: 8),
            _buildInfoRow("Vị trí gốc:", song.data),
            const SizedBox(height: 8),
            _buildInfoRow("Ngày cập nhật:", dateString),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Đóng"),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        Text(value, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  Widget _buildSongList(List<SongModel> songs, {bool isCustomFile = false}) {
    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final isVideo = song.genre == "VideoFile";
        final icon = isVideo ? Icons.movie : Icons.music_note;
        return ListTile(
          leading: (isCustomFile || isVideo)
              ? Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: Colors.white),
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
          subtitle: Text(
            (song.artist == null || song.artist == '<unknown>')
                ? File(song.data).parent.path
                : song.artist!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'info') {
                _showSongInfo(song);
              }
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
                value: 'info',
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue),
                    SizedBox(width: 8),
                    Text("Thông tin"),
                  ],
                ),
              ),
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
        final isCustom =
            song.genre == "CustomFile" ||
            song.genre == "FolderFile" ||
            song.genre == "VideoFile";
        final isVideo = song.genre == "VideoFile";

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
                            ? Icon(
                                isVideo ? Icons.movie : Icons.music_note,
                                size: 40,
                              )
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
                          onPressed: () {
                            if (player.hasPrevious) {
                              player.seekToPrevious();
                            } else {
                              final indices = player.effectiveIndices;
                              if (indices != null && indices.isNotEmpty) {
                                player.seek(Duration.zero, index: indices.last);
                              }
                            }
                          },
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
                          onPressed: () {
                            if (player.hasNext) {
                              player.seekToNext();
                            } else {
                              final indices = player.effectiveIndices;
                              if (indices != null && indices.isNotEmpty) {
                                player.seek(
                                  Duration.zero,
                                  index: indices.first,
                                );
                              }
                            }
                          },
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

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  StreamSubscription<bool>? _playingSubscription;
  bool _isVolumeVisible = false;
  Timer? _volumeTimer;
  double _currentVolume = 1.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20), // Quay 1 vòng hết 20 giây
    );

    // Lấy âm lượng hiện tại
    _currentVolume = AudioManager().player.volume;

    // Lắng nghe trạng thái phát nhạc để điều khiển đĩa quay
    final player = AudioManager().player;
    _playingSubscription = player.playingStream.listen((playing) {
      if (playing) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _volumeTimer?.cancel();
    _playingSubscription?.cancel();
    super.dispose();
  }

  void _toggleVolumeControl() {
    setState(() {
      _isVolumeVisible = !_isVolumeVisible;
    });
    if (_isVolumeVisible) {
      _resetVolumeTimer();
    } else {
      _volumeTimer?.cancel();
    }
  }

  void _resetVolumeTimer() {
    _volumeTimer?.cancel();
    _volumeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isVolumeVisible = false;
        });
      }
    });
  }

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
          final isCustom =
              song.genre == "CustomFile" ||
              song.genre == "FolderFile" ||
              song.genre == "VideoFile";
          final isVideo = song.genre == "VideoFile";

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
                    child: RotationTransition(
                      turns: _controller,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          shape: BoxShape.circle, // Chuyển thành hình tròn
                          border: Border.all(
                            color: Colors.black,
                            width: 8,
                          ), // Viền đĩa nhạc
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          // Cắt ảnh theo hình tròn
                          child: Center(
                            child: isCustom
                                ? Icon(
                                    isVideo ? Icons.movie : Icons.music_note,
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
                  if (!isCustom &&
                      song.artist != null &&
                      song.artist != '<unknown>') ...[
                    const SizedBox(height: 8),
                    Text(
                      song.artist!,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Điều chỉnh âm lượng
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      IconButton(
                        icon: Icon(
                          _currentVolume == 0
                              ? Icons.volume_off
                              : Icons.volume_up,
                          color: Colors.white70,
                        ),
                        onPressed: _toggleVolumeControl,
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: _isVolumeVisible ? 200 : 0,
                        curve: Curves.easeInOut,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          child: SizedBox(
                            width: 200,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2.0,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6.0,
                                ),
                                activeTrackColor: Colors.cyan,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                              ),
                              child: Slider(
                                value: _currentVolume,
                                onChanged: (value) {
                                  setState(() => _currentVolume = value);
                                  player.setVolume(value);
                                  _resetVolumeTimer(); // Reset timer khi đang kéo
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
                                ? Colors.cyan
                                : Colors.white70,
                            tooltip: 'Phát ngẫu nhiên',
                            onPressed: () async {
                              if (shuffleModeEnabled) {
                                // Tắt ngẫu nhiên, bật lặp lại danh sách
                                await player.setShuffleModeEnabled(false);
                                await player.setLoopMode(LoopMode.all);
                              } else {
                                // Bật ngẫu nhiên, vẫn giữ lặp danh sách để phát liên tục
                                await player.setLoopMode(LoopMode.all);
                                await player.setShuffleModeEnabled(true);
                                await player.shuffle();
                              }
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
                        onPressed: () {
                          if (player.hasPrevious) {
                            player.seekToPrevious();
                          } else {
                            final indices = player.effectiveIndices;
                            if (indices != null && indices.isNotEmpty) {
                              player.seek(Duration.zero, index: indices.last);
                            }
                          }
                        },
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
                        onPressed: () {
                          if (player.hasNext) {
                            player.seekToNext();
                          } else {
                            final indices = player.effectiveIndices;
                            if (indices != null && indices.isNotEmpty) {
                              player.seek(Duration.zero, index: indices.first);
                            }
                          }
                        },
                      ),
                      // Nút Repeat (Lặp lại)
                      StreamBuilder<bool>(
                        stream: player.shuffleModeEnabledStream,
                        builder: (context, snapshot) {
                          final shuffleEnabled = snapshot.data ?? false;
                          return StreamBuilder<LoopMode>(
                            stream: player.loopModeStream,
                            builder: (context, snapshot) {
                              final loopMode = snapshot.data ?? LoopMode.all;
                              Icon icon;
                              String tooltip;
                              Color color;

                              // Logic hiển thị:
                              // 1. Nếu Shuffle đang bật -> Nút Repeat màu trắng (dù loopMode là all)
                              // 2. Nếu Shuffle tắt -> Nút Repeat màu xanh (theo chế độ One hoặc All)
                              if (shuffleEnabled) {
                                icon = const Icon(Icons.repeat);
                                tooltip = 'Lặp lại';
                                color = Colors.white70;
                              } else {
                                if (loopMode == LoopMode.one) {
                                  icon = const Icon(Icons.repeat_one);
                                  tooltip = 'Lặp 1 bài';
                                  color = Colors.cyan;
                                } else {
                                  // Mặc định là Lặp danh sách (LoopMode.all hoặc off)
                                  icon = const Icon(Icons.repeat);
                                  tooltip = 'Lặp danh sách';
                                  color = Colors.cyan;
                                }
                              }

                              return IconButton(
                                icon: icon,
                                color: color,
                                tooltip: tooltip,
                                onPressed: () async {
                                  if (shuffleEnabled) {
                                    // Nếu đang Shuffle -> Tắt Shuffle, chuyển về Lặp danh sách
                                    await player.setShuffleModeEnabled(false);
                                    await player.setLoopMode(LoopMode.all);
                                  } else {
                                    // Nếu đang Lặp -> Chuyển đổi qua lại giữa One và All
                                    if (loopMode == LoopMode.one) {
                                      await player.setLoopMode(LoopMode.all);
                                    } else {
                                      await player.setLoopMode(LoopMode.one);
                                    }
                                  }
                                },
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

class SongSearchDelegate extends SearchDelegate {
  final List<SongModel> songs;
  final bool isCustomFile;

  SongSearchDelegate({required this.songs, required this.isCustomFile});

  // Hàm loại bỏ dấu tiếng Việt để hỗ trợ tìm kiếm không dấu
  String _removeDiacritics(String str) {
    const withDia =
        'áàảãạăắằẳẵặâấầẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđÁÀẢÃẠĂẮẰẲẴẶÂẤẦẨẪẬÉÈẺẼẸÊẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌÔỐỒỔỖỘƠỚỜỞỠỢÚÙỦŨỤƯỨỪỬỮỰÝỲỶỸỴĐ';
    const withoutDia =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydAAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';

    StringBuffer sb = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      String char = str[i];
      int index = withDia.indexOf(char);
      if (index >= 0) {
        sb.write(withoutDia[index]);
      } else {
        sb.write(char);
      }
    }
    return sb.toString();
  }

  @override
  String get searchFieldLabel => 'Tìm bài hát, nghệ sĩ...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white54),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildList(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildList(context);
  }

  Widget _buildList(BuildContext context) {
    // Chuẩn hóa từ khóa: chữ thường + bỏ dấu
    final queryUnaccented = _removeDiacritics(query.toLowerCase());

    // Lọc danh sách theo từ khóa (Title hoặc Artist)
    final suggestions = songs.where((song) {
      final titleUnaccented = _removeDiacritics(song.title.toLowerCase());
      final artistUnaccented = _removeDiacritics(
        (song.artist ?? '').toLowerCase(),
      );
      return titleUnaccented.contains(queryUnaccented) ||
          artistUnaccented.contains(queryUnaccented);
    }).toList();

    if (suggestions.isEmpty) {
      return Center(
        child: Text(
          'Không tìm thấy kết quả cho "$query"',
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }

    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final song = suggestions[index];
        final isVideo = song.genre == "VideoFile";
        final icon = isVideo ? Icons.movie : Icons.music_note;
        return ListTile(
          leading: (isCustomFile || isVideo)
              ? Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: Colors.white),
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
          title: Text(song.title, style: const TextStyle(color: Colors.white)),
          subtitle: Text(
            (song.artist == null || song.artist == '<unknown>')
                ? File(song.data).parent.path
                : song.artist!,
            style: const TextStyle(color: Colors.white70),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            // Tìm vị trí thực của bài hát trong danh sách gốc để giữ context playlist
            final originalIndex = songs.indexOf(song);

            // Đóng tìm kiếm
            close(context, null);

            // Phát nhạc và mở màn hình Player
            AudioManager().playSong(songs, originalIndex);
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
