import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

class AudioManager {
  // Singleton pattern
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;
  AudioManager._internal();

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
      final playlist = ConcatenatingAudioSource(
        children: songs.map((song) {
          return AudioSource.uri(
            Uri.parse(song.uri ?? ""),
            tag:
                song, // Lưu đối tượng SongModel vào tag để dùng hiển thị UI sau này
          );
        }).toList(),
      );
      await player.setAudioSource(playlist, initialIndex: initialIndex);
      player.play();
    } catch (e) {
      print("Lỗi phát nhạc: $e");
    }
  }
}
