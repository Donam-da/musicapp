import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:audio_session/audio_session.dart';

class AudioManager {
  // Singleton pattern
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;

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

    return songs;
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
