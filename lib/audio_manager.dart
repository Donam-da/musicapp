import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

class AudioManager {
  // Singleton pattern
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;

  AudioManager._internal() {
    // Lắng nghe trạng thái player để tự động xử lý khi bài hát kết thúc
    // Đảm bảo nhạc luôn phát tiếp (theo chế độ đã chọn) thay vì dừng lại
    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (player.loopMode == LoopMode.one) {
          player.seek(Duration.zero);
          player.play();
        } else {
          if (player.loopMode == LoopMode.off) {
            player.setLoopMode(LoopMode.all);
          }
          final indices = player.effectiveIndices;
          if (indices != null && indices.isNotEmpty) {
            player.seek(Duration.zero, index: indices.first);
            player.play();
          }
        }
      }
    });
  }

  final AudioPlayer player = AudioPlayer();
  final OnAudioQuery audioQuery = OnAudioQuery();

  // Lấy danh sách bài hát từ bộ nhớ máy
  Future<List<SongModel>> getSongs() async {
    return await audioQuery.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
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
      print("Lỗi phát nhạc: $e");
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
      print("Lỗi phát file tùy chọn: $e");
    }
  }
}
