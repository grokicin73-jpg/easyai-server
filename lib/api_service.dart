import 'dart:math';
import 'package:dio/dio.dart';
import 'package:android_id/android_id.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

class ApiService {
  String reviewCode = '';

  static const _storage = FlutterSecureStorage();
  static const _sessionKey = 'easyai_instagram_session_v1';
  static Future<String>? _credentialFuture;

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://easyai-server.onrender.com/',
      connectTimeout: const Duration(seconds: 180),
      receiveTimeout: const Duration(seconds: 180),
    ),
  );

  // Server bilan aloqani tekshirish
  Future<bool> testConnection() async {
    try {
      final response = await _dio.get('/');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Google Play xaridini tekshirish
  Future<bool> verifyPurchase({
    required String purchaseToken,
    required String productId,
  }) async {
    try {
      const androidIdPlugin = AndroidId();
      final deviceId = await androidIdPlugin.getId();

      final response = await _dio.post(
        '/api/verify-purchase',
        data: {
          'purchaseToken': purchaseToken,
          'productId': productId,
          'deviceId': deviceId,
        },
      );

      return response.statusCode == 200 &&
          response.data is Map &&
          response.data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // Veo orqali video yaratish
  Future<String> generateVideoWithVeo({
    required String prompt,
    required String selectedModel,
    String? imagePath,
  }) async {
    const androidIdPlugin = AndroidId();
    final deviceId = await androidIdPlugin.getId();

    try {
      final formData = FormData.fromMap({
        'prompt': prompt,
        'selectedModel': selectedModel,
        'deviceId': deviceId,
        'reviewCode': reviewCode.trim(),
        if (imagePath != null && imagePath.isNotEmpty)
          'image': await MultipartFile.fromFile(imagePath),
      });

      final response = await _dio.post(
        '/api/generate-video',
        data: formData,
      );

      if (response.statusCode == 200 &&
          response.data is Map &&
          response.data['success'] == true) {
        final videoUrl = response.data['videoUrl'];

        if (videoUrl is String && videoUrl.isNotEmpty) {
          return videoUrl;
        }
      }
    } on DioException catch (e) {
      final errorData = e.response?.data;

      if (e.response?.statusCode == 403 &&
          errorData is Map &&
          errorData['code'] == 'FREE_LIMIT_REACHED') {
        throw Exception('FREE_LIMIT_REACHED');
      }

      rethrow;
    }

    throw Exception('VIDEO_GENERATION_FAILED');
  }

  // Shu ilova uchun maxfiy Instagram ulanish kaliti
  static Future<String> _loadCredential() async {
    final saved = await _storage.read(key: _sessionKey);

    if (saved != null &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(saved)) {
      return saved;
    }

    final random = Random.secure();

    final credential = List.generate(
      32,
      (_) => random
          .nextInt(256)
          .toRadixString(16)
          .padLeft(2, '0'),
    ).join();

    await _storage.write(
      key: _sessionKey,
      value: credential,
    );

    return credential;
  }

  // Serverda Instagram ulanish sessiyasini tayyorlash
  Future<Options> _instagramOptions() async {
    final pending = _credentialFuture ??= _loadCredential();

    String credential;

    try {
      credential = await pending;
    } catch (_) {
      _credentialFuture = null;
      rethrow;
    }

    final options = Options(
      headers: {
        'Authorization': 'Bearer $credential',
      },
    );

    await _dio.post(
      '/api/instagram/session',
      options: options,
    );

    return options;
  }

  // Instagram ruxsat oynasini telefon brauzerida ochish
  Future<void> connectInstagram() async {
    final options = await _instagramOptions();

    final response = await _dio.post(
      '/api/instagram/connect',
      options: options,
    );

    final data = response.data;

    if (data is! Map ||
        data['success'] != true ||
        data['connectUrl'] is! String) {
      throw Exception('INSTAGRAM_CONNECT_FAILED');
    }

    final url = Uri.parse(data['connectUrl'] as String);

    if (url.scheme != 'https' ||
        url.host != 'easyai-server.onrender.com' ||
        url.path != '/instagram/login') {
      throw Exception('INVALID_INSTAGRAM_URL');
    }

    final opened = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );

    if (!opened) {
      throw Exception('INSTAGRAM_BROWSER_FAILED');
    }
  }

  // Instagram ulanganligini tekshirish
  Future<Map<String, dynamic>> getInstagramStatus() async {
    final options = await _instagramOptions();

    final response = await _dio.get(
      '/api/instagram/status',
      options: options,
    );

    final data = response.data;

    if (data is! Map || data['success'] != true) {
      throw Exception('INSTAGRAM_STATUS_FAILED');
    }

    return Map<String, dynamic>.from(data);
  }

  // EasyAI serveridagi Instagram ulanishini o‘chirish
  Future<void> disconnectInstagram() async {
    final options = await _instagramOptions();

    await _dio.delete(
      '/api/instagram/connection',
      options: options,
    );
  }
  Future<String> uploadInstagramVideo(String videoPath) async {
    final options = await _instagramOptions();

    final formData = FormData.fromMap({
      'video': await MultipartFile.fromFile(
        videoPath,
        filename: 'video.mp4',
      ),
    });

    final response = await _dio.post(
      '/api/instagram/videos/upload',
      options: options.copyWith(
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
      ),
      data: formData,
    );

    final data = response.data;

    if (data is! Map ||
        data['success'] != true ||
        data['videoUrl'] is! String) {
      throw const FormatException('VIDEO_UPLOAD_FAILED');
    }

    final videoUrl = data['videoUrl'] as String;
    final url = Uri.tryParse(videoUrl);

    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'easyai-server.onrender.com' ||
        url.hasPort ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        !RegExp(r'^/videos/[a-zA-Z0-9_-]+\.mp4$')
            .hasMatch(url.path)) {
      throw const FormatException('INVALID_VIDEO_URL');
    }

    return videoUrl;
  }
  String createInstagramReelRequestId() {
    final random = Random.secure();

    return List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void _checkInstagramReelId(String value) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      throw ArgumentError('INVALID_INSTAGRAM_REEL_ID');
    }
  }

  Map<String, dynamic> _instagramReelData(
    Response<dynamic> response,
  ) {
    final data = response.data;

    if (data is! Map) {
      throw const FormatException('INVALID_INSTAGRAM_RESPONSE');
    }

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> prepareInstagramReel({
    required String requestId,
    required String videoUrl,
    required String caption,
  }) async {
    _checkInstagramReelId(requestId);

    final options = await _instagramOptions();

    final response = await _dio.post(
      '/api/instagram/reels/prepare',
      options: options,
      data: {
        'requestId': requestId,
        'videoUrl': videoUrl,
        'caption': caption,
      },
    );

    return _instagramReelData(response);
  }

  Future<Map<String, dynamic>> getInstagramReelStatus(
    String jobId,
  ) async {
    _checkInstagramReelId(jobId);

    final options = await _instagramOptions();

    final response = await _dio.get(
      '/api/instagram/reels/$jobId/status',
      options: options,
    );

    return _instagramReelData(response);
  }

  Future<Map<String, dynamic>> publishInstagramReel({
    required String jobId,
    required bool confirmed,
  }) async {
    _checkInstagramReelId(jobId);

    if (!confirmed) {
      throw StateError('PUBLISH_CONFIRMATION_REQUIRED');
    }

    final options = await _instagramOptions();

    final response = await _dio.post(
      '/api/instagram/reels/$jobId/publish',
      options: options,
      data: {
        'confirm': true,
      },
    );

    return _instagramReelData(response);
  }
 Map<String, dynamic> _businessData(Response<dynamic> response) {
    final data = response.data;

    if (data is! Map || data['success'] != true) {
      throw const FormatException('INVALID_BUSINESS_RESPONSE');
    }

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> getInstagramProducts() async {
    final options = await _instagramOptions();

    final response = await _dio.get(
      '/api/instagram/business/products',
      options: options,
    );

    return _businessData(response);
  }

  Future<void> saveInstagramProduct({
    required String productId,
    required String name,
    required String description,
    required int priceMinor,
    required String currency,
    required bool available,
  }) async {
    _checkInstagramReelId(productId);

    final options = await _instagramOptions();

    final response = await _dio.put(
      '/api/instagram/business/products/$productId',
      options: options,
      data: {
        'name': name,
        'description': description,
        'priceMinor': priceMinor,
        'currency': currency,
        'available': available,
      },
    );

    _businessData(response);
  }

  Future<void> deleteInstagramProduct(String productId) async {
    _checkInstagramReelId(productId);

    final options = await _instagramOptions();

    final response = await _dio.delete(
      '/api/instagram/business/products/$productId',
      options: options,
    );

    _businessData(response);
  } 
  Future<bool> setInstagramAutoReplyEnabled(bool enabled) async {
    final options = await _instagramOptions();

    final response = await _dio.put(
      '/api/instagram/business/settings',
      options: options,
      data: {
        'autoReplyEnabled': enabled,
      },
    );

    final data = _businessData(response);
    final saved = data['autoReplyEnabled'];

    if (saved is! bool || saved != enabled) {
      throw const FormatException('INVALID_SETTINGS_RESPONSE');
    }

    return saved;
  }
}