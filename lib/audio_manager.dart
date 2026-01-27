import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_session/audio_session.dart';
import 'package:photo_manager/photo_manager.dart';

class AudioManager {
  // Singleton pattern
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;

  int? _previousIndex;

  PageController? pageController;

  // Map để tra cứu ID thực từ hệ thống dựa trên đường dẫn file
  Map<String, int> _pathToIdMap = {};
  Map<String, int> get pathToIdMap => _pathToIdMap;

  AudioManager._internal() {
    _initAudioSession();
    // Lắng nghe trạng thái player để tự động xử lý khi bài hát kết thúc
    // và phát lại playlist khi nó kết thúc.
    player.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
        // Khi playlist kết thúc (chỉ xảy ra nếu LoopMode.off),
        // hoặc có thể do một số lỗi không mong muốn, ta sẽ tự động phát lại từ đầu.
        // Điều này đảm bảo nhạc không bao giờ dừng.
        // `just_audio` sẽ tự xử lý LoopMode.one và LoopMode.all,
        // nhưng listener này hoạt động như một phương án dự phòng chắc chắn.
        final effectiveIndices = player.effectiveIndices;
        if (effectiveIndices != null && effectiveIndices.isNotEmpty) {
          await player.seek(Duration.zero, index: effectiveIndices.first);
          player.play();
        }
      }
    });

    // Lắng nghe thay đổi bài hát để phát hiện khi hết vòng lặp (LoopMode.all)
    // và thực hiện xáo trộn lại danh sách để vòng sau có thứ tự mới.
    player.currentIndexStream.listen((index) {
      if (index != null && _previousIndex != null) {
        if (player.shuffleModeEnabled) {
          final indices = player.effectiveIndices;
          if (indices != null && indices.isNotEmpty) {
            // Nếu bài trước đó là bài cuối cùng trong danh sách xáo trộn hiện tại
            // VÀ bài hiện tại là bài đầu tiên -> Nghĩa là vừa hết 1 vòng.
            if (_previousIndex == indices.last && index == indices.first) {
              player.shuffle(); // Tạo thứ tự ngẫu nhiên mới cho vòng tiếp theo
            }
          }
        }
      }
      _previousIndex = index;
    });
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  final AudioPlayer player = AudioPlayer();
  final OnAudioQuery audioQuery = OnAudioQuery();

  // Lấy danh sách bài hát từ bộ nhớ máy
  Future<List<SongModel>> getSongs() async {
    final songs = await audioQuery.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    // Cập nhật map tra cứu ID thực
    _pathToIdMap = {for (var s in songs) s.data: s.id};

    // Tập hợp các đường dẫn đã quét để tránh trùng lặp
    final Set<String> processedPaths = songs.map((s) => s.data).toSet();
    List<SongModel> videoSongs = [];

    // CÁCH 1: Quét Video sử dụng PhotoManager (Hệ thống)
    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      if (ps.isAuth) {
        final List<AssetPathEntity> albums =
            await PhotoManager.getAssetPathList(type: RequestType.video);

        for (final album in albums) {
          final count = await album.assetCountAsync;
          final videos = await album.getAssetListRange(start: 0, end: count);
          for (final video in videos) {
            // Chỉ lấy Video hoặc file có đuôi .mp4
            if (video.type != AssetType.video) {
              final title = video.title?.toLowerCase() ?? '';
              if (!title.endsWith('.mp4')) continue;
            }

            final file = await video.file; // Lấy file thực tế
            if (file != null && !processedPaths.contains(file.path)) {
              videoSongs.add(
                SongModel({
                  "_id":
                      int.tryParse(video.id) ??
                      video
                          .id
                          .hashCode, // Cố gắng lấy ID thực từ hệ thống để tìm ảnh bìa
                  "_data": file.path,
                  "title": video.title ?? file.path.split('/').last,
                  "artist": "<Video>",
                  "genre": "VideoFile",
                }),
              );
              processedPaths.add(file.path);
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Lỗi quét video: $e");
    }

    // CÁCH 2: Quét thủ công các thư mục phổ biến (Manual Scan)
    // Đây là "cách khác" để tìm file khi MediaStore bị lỗi hoặc chưa cập nhật
    final commonPaths = [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Movies',
      '/storage/emulated/0/Video',
      '/storage/emulated/0/Zalo',
      '/storage/emulated/0/Facebook',
    ];

    for (final path in commonPaths) {
      final dir = Directory(path);
      try {
        if (await dir.exists()) {
          // Quét đệ quy để tìm sâu bên trong
          await for (final entity in dir.list(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is File) {
              final p = entity.path;
              if (p.toLowerCase().endsWith('.mp4') &&
                  !processedPaths.contains(p)) {
                final fileName = p.split(Platform.pathSeparator).last;
                final parentName = entity.parent.path
                    .split(Platform.pathSeparator)
                    .last;
                videoSongs.add(
                  SongModel({
                    "_id": p.hashCode,
                    "_data": p,
                    "title": fileName,
                    "artist": parentName,
                    "genre": "VideoFile",
                  }),
                );
                processedPaths.add(p);
              }
            }
          }
        }
      } catch (e) {
        // Bỏ qua lỗi quyền truy cập ở các thư mục con
        // debugPrint("Lỗi quét thủ công $path: $e");
      }
    }

    return [...songs, ...videoSongs];
  }

  // Thiết lập danh sách phát và phát bài hát tại index được chọn
  Future<void> playSong(List<SongModel> songs, int initialIndex) async {
    try {
      // Đảm bảo âm lượng player được bật tối đa
      await player.setVolume(1.0);

      // Đảm bảo luôn có chế độ lặp được chọn (mặc định là Lặp danh sách nếu đang tắt)
      if (player.loopMode == LoopMode.off) {
        await player.setLoopMode(LoopMode.all);
      }

      final playlist = ConcatenatingAudioSource(
        children: songs.map((song) {
          Uri audioUri;
          if (song.uri != null && song.uri!.isNotEmpty) {
            audioUri = Uri.parse(song.uri!);
          } else {
            // Sử dụng Uri.file cho đường dẫn file cục bộ để đảm bảo mã hóa đúng các ký tự đặc biệt
            audioUri = Uri.file(song.data);
          }
          return AudioSource.uri(
            audioUri,
            tag:
                song, // Lưu đối tượng SongModel vào tag để dùng hiển thị UI sau này
          );
        }).toList(),
      );
      await player.setAudioSource(playlist, initialIndex: initialIndex);
      await player.play(); // Đợi lệnh play thực hiện xong để bắt lỗi nếu có
    } catch (e) {
      debugPrint("Lỗi phát nhạc: $e");
    }
  }

  // Phát danh sách các file được chọn từ FilePicker
  Future<void> playLocalFiles(List<String> filePaths) async {
    try {
      final playlist = ConcatenatingAudioSource(
        children: filePaths.map((path) {
          // Tạo SongModel giả lập từ đường dẫn file để UI hiển thị được tên
          final fileName = path.split('/').last;
          final song = SongModel({
            "_id": path.hashCode,
            "_data": path,
            "title": fileName,
            "artist": "Tệp tùy chọn",
          });

          return AudioSource.uri(Uri.file(path), tag: song);
        }).toList(),
      );
      await player.setAudioSource(playlist);
      player.play();
    } catch (e) {
      debugPrint("Lỗi phát file tùy chọn: $e");
    }
  }
}
