import 'package:dio/dio.dart';

class ApiService {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://easyai-backend-1-srn1.onrender.com',
      connectTimeout: const Duration(seconds: 180),
      receiveTimeout: const Duration(seconds: 180),
    ),
  );

  // Server bilan aloqani tekshirish uchun
  Future<bool> testConnection() async {
    try {
      final response = await _dio.get('/');
      return response.statusCode == 200;
    } catch (e) {
      print("Aloqa xatosi: $e");
      return false;
    }
  }

  // Veo orqali video yaratish funksiyasi
  Future<String> generateVideoWithVeo({
    required String prompt,
    required String selectedModel,
  }) async {
    try {
      print("SO'ROV KETYAPTI...");
      final response = await _dio.post(
        '/api/generate-video',
        data: {
          'prompt': prompt,
          'selectedModel': selectedModel,
        },
      );
      print("SERVER JAVOBI: ${response.data}");

      if (response.statusCode == 200 &&
          response.data is Map &&
          response.data['success'] == true) {
        final videoUrl = response.data['message'];

        if (videoUrl is String && videoUrl.isNotEmpty) {
          return videoUrl;
        }
      }
    } catch (e) {
      print("XATO YUZ BERDI: $e");
      rethrow;
    }
    throw Exception('Video yaratishda xatolik yuz berdi');
  }
}