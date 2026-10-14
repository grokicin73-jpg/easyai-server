import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';

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
      throw Exception(
        'Videoni yuklab bo\'lmadi. Kod: ${response.statusCode}',
      );
    }

    final String filePath =
        '${Directory.systemTemp.path}/easyai_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final File file = File(filePath);
    await file.writeAsBytes(response.bodyBytes);

    await Gal.putVideo(file.path);

    if (await file.exists()) {
      await file.delete();
    }
  }
}