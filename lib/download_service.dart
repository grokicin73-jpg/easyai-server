import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:http/http.dart' as http;

class DownloadService {
  static Future<void> downloadVideo(String videoUrl) async {
    final String cleanUrl = videoUrl.trim();

    if (cleanUrl.isEmpty) {
      throw Exception('Video manzili topilmadi.');
    }

    final Uri? uri = Uri.tryParse(cleanUrl);

    if (uri == null || !uri.hasScheme) {
      throw Exception('Video manzili noto\'g\'ri.');
    }

    final http.Response response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Videoniki yuklab bo\'lmadi. Kod: ${response.statusCode}');
    }

   final Uint8List videoBytes = response.bodyBytes;
    await FileSaver.instance.saveFile(
      name: 'video_${DateTime.now().millisecondsSinceEpoch}',
      bytes: videoBytes,
      fileExtension: 'mp4',
      mimeType: MimeType.mpeg,
    );
  }
}