import 'dart:math';

import 'package:dio/dio.dart';
import 'package:android_id/android_id.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

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

  Future<Map<String, String>> getJarvisHeaders({
    required String language,
  }) async {
    final credential = await _credential();

    const androidIdPlugin = AndroidId();
    final rawId = await androidIdPlugin.getId();
    final deviceId = rawId?.trim().toLowerCase() ?? '';
    print('EASYAI_DEVICE_ID: $deviceId');

    if (!RegExp(r'^[a-f0-9]{16}$').hasMatch(deviceId)) {
      throw StateError('JARVIS_DEVICE_ID_UNAVAILABLE');
    }

    final headers = <String, String>{
      'Authorization': 'Bearer $credential',
      'x-easyai-device-id': deviceId,
      'x-jarvis-language': {
        'English': 'en',
        'Кыргызча': 'ky',
        'Русский': 'ru',
        'Türkçe': 'tr',
      }[language] ?? 'en',
    };

    final response = await _dio.post(
      '/api/jarvis/session',
      options: Options(
        headers: headers,
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    final data = response.data;

    if (data is! Map || data['success'] != true) {
      throw StateError('JARVIS_SESSION_FAILED');
    }

    return headers;
  }

  String createJarvisRequestId() => _randomId();

  Future<bool> buyJarvisCredits() async {
    final store = InAppPurchase.instance;

    if (!await store.isAvailable()) return false;

    final result = await store.queryProductDetails({
      'credits_500',
    });

    if (result.error != null || result.productDetails.length != 1) {
      return false;
    }

    return store.buyConsumable(
      purchaseParam: PurchaseParam(
        productDetails: result.productDetails.single,
      ),
      autoConsume: false,
    );
  }

  Future<Map<String, dynamic>> getCreditAccount(
    String language,
  ) async {
    final headers = await getJarvisHeaders(language: language);

    final response = await _dio.get(
      '/api/jarvis/account',
      options: Options(
        headers: headers,
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    final data = response.data;

    if (data is! Map || data['success'] != true) {
      throw const FormatException('ACCOUNT_UNAVAILABLE');
    }

    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> getAutomationTasks(
    String language,
  ) async {
    final headers = await getJarvisHeaders(language: language);

    final response = await _dio.get(
      '/api/jarvis/tasks',
      options: Options(headers: headers),
    );

    final data = response.data;

    if (data is! Map ||
        data['success'] != true ||
        data['tasks'] is! List) {
      throw const FormatException('TASKS_UNAVAILABLE');
    }

    return (data['tasks'] as List)
        .map(
          (item) => Map<String, dynamic>.from(item as Map),
        )
        .toList();
  }

  Future<Map<String, dynamic>> startAutomation({
    required String language,
    required String requestId,
    required String command,
    required String title,
    required String prompt,
    required String caption,
  }) async {
    final headers = await getJarvisHeaders(language: language);

    final response = await _dio.post(
      '/api/jarvis/tasks',
      options: Options(headers: headers),
      data: {
        'requestId': requestId,
        'command': command,
        'draft': {
          'title': title,
          'prompt': prompt,
          'caption': caption,
        },
      },
    );

    final data = response.data;

    if (data is! Map ||
        data['success'] != true ||
        data['task'] is! Map) {
      throw const FormatException('TASK_UNAVAILABLE');
    }

    return Map<String, dynamic>.from(data['task'] as Map);
  }

  Future<void> checkAutomationTask(
    String language,
    String id,
  ) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
      throw ArgumentError('INVALID_TASK_ID');
    }

    final headers = await getJarvisHeaders(language: language);

    await _dio.post(
      '/api/jarvis/tasks/$id/check',
      options: Options(headers: headers),
    );
  }

  Future<Options> _deviceOptions() async {
    final credential = await _credential();

    return Options(
      headers: {
        'Authorization': 'Bearer $credential',
      },
    );
  }

  Future<bool> testConnection() async {
    try {
      final response = await _dio.get('/');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyPurchase({
    required String purchaseToken,
    required String productId,
  }) async {
    try {
      const androidIdPlugin = AndroidId();
      final deviceId = await androidIdPlugin.getId();

      final response = await _dio.post(
        '/api/verify-purchase',
        options: await _deviceOptions(),
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
        options: await _deviceOptions(),
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
    } on DioException catch (error) {
      final data = error.response?.data;

      if (error.response?.statusCode == 403 &&
          data is Map &&
          data['code'] == 'FREE_LIMIT_REACHED') {
        throw Exception('FREE_LIMIT_REACHED');
      }

      rethrow;
    }

    throw Exception('VIDEO_GENERATION_FAILED');
  }

  static String _randomId() {
    final random = Random.secure();

    return List.generate(
      32,
      (_) => random
          .nextInt(256)
          .toRadixString(16)
          .padLeft(2, '0'),
    ).join();
  }

  static Future<String> _loadCredential() async {
    final saved = await _storage.read(key: _sessionKey);

    if (saved != null &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(saved)) {
      return saved;
    }

    final credential = _randomId();

    await _storage.write(
      key: _sessionKey,
      value: credential,
    );

    return credential;
  }

  static Future<String> _credential() async {
    final pending = _credentialFuture ??= _loadCredential();

    try {
      return await pending;
    } catch (_) {
      _credentialFuture = null;
      rethrow;
    }
  }

  Future<Options> _instagramOptions() async {
    final credential = await _credential();

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

  String createInstagramReelRequestId() => _randomId();

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

  Map<String, dynamic> _businessData(
    Response<dynamic> response,
  ) {
    final data = response.data;

    if (data is! Map || data['success'] != true) {
      throw const FormatException('INVALID_BUSINESS_RESPONSE');
    }

    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> getInstagramProducts({
    String search = '',
    String? cursor,
    int limit = 50,
  }) async {
    final query = search.trim();

    if (query.length > 120) {
      throw ArgumentError('INVALID_CATALOG_SEARCH');
    }

    if (limit < 1 || limit > 50) {
      throw ArgumentError('INVALID_CATALOG_PAGE_SIZE');
    }

    if (cursor != null &&
        cursor.isNotEmpty &&
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(cursor)) {
      throw ArgumentError('INVALID_CATALOG_CURSOR');
    }

    final options = await _instagramOptions();

    final response = await _dio.get(
      '/api/instagram/business/products',
      options: options,
      queryParameters: {
        'limit': limit,
        if (query.isNotEmpty) 'q': query,
        if (cursor != null && cursor.isNotEmpty)
          'cursor': cursor,
      },
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

  Future<void> deleteInstagramProduct(
    String productId,
  ) async {
    _checkInstagramReelId(productId);

    final options = await _instagramOptions();

    final response = await _dio.delete(
      '/api/instagram/business/products/$productId',
      options: options,
    );

    _businessData(response);
  }

  Future<bool> setInstagramAutoReplyEnabled(
    bool enabled,
  ) async {
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
  Future<String> getInstagramWhatsAppPhone() async {
    final options = await _instagramOptions();

    final response = await _dio.get(
      '/api/instagram/business/contact',
      options: options,
    );

    final data = _businessData(response);
    final phone = data['whatsappPhone'];

    if (phone is! String ||
        (phone.isNotEmpty &&
            !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone))) {
      throw const FormatException('INVALID_CONTACT_RESPONSE');
    }

    return phone;
  }

  Future<String> saveInstagramWhatsAppPhone(
    String input,
  ) async {
    final value = input.trim();

    if (value.length > 40 ||
        (value.isNotEmpty &&
            !RegExp(r'^\+?[\d\s()-]+$').hasMatch(value))) {
      throw ArgumentError('INVALID_WHATSAPP_PHONE');
    }

    final digits = value.replaceAll(RegExp(r'\D'), '');

    if (value.isNotEmpty &&
        !RegExp(r'^[1-9]\d{7,14}$').hasMatch(digits)) {
      throw ArgumentError('INVALID_WHATSAPP_PHONE');
    }

    final phone = value.isEmpty ? '' : '+$digits';
    final options = await _instagramOptions();

    final response = await _dio.put(
      '/api/instagram/business/contact',
      options: options,
      data: {
        'whatsappPhone': phone,
      },
    );

    final data = _businessData(response);
    final saved = data['whatsappPhone'];

    if (saved is! String || saved != phone) {
      throw const FormatException('CONTACT_SAVE_NOT_CONFIRMED');
    }

    return saved;
  }

  Future<void> reportAIContent({
    required String contentType,
    required String reason,
    required String language,
    String details = '',
    String content = '',
    String prompt = '',
    String model = '',
    String videoUrl = '',
  }) async {
    const allowedTypes = {
      'video',
      'chat',
      'voice',
    };

    const allowedReasons = {
      'sexual',
      'violence',
      'hate',
      'child_safety',
      'misleading',
      'other',
    };

    if (!allowedTypes.contains(contentType) ||
        !allowedReasons.contains(reason)) {
      throw ArgumentError('INVALID_CONTENT_REPORT');
    }

    if (details.length > 2000 ||
        content.length > 20000 ||
        prompt.length > 20000 ||
        model.length > 100 ||
        language.length > 40 ||
        videoUrl.length > 4096) {
      throw ArgumentError('CONTENT_REPORT_TOO_LONG');
    }

    final response = await _dio.post(
      '/api/content-reports',
      data: {
        'contentType': contentType,
        'reason': reason,
        'language': language,
        'details': details.trim(),
        'content': content,
        'prompt': prompt,
        'model': model,
        'videoUrl': videoUrl,
      },
      options: Options(
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );

    final data = response.data;

    if ((response.statusCode != 200 &&
            response.statusCode != 201) ||
        data is! Map ||
        data['success'] != true ||
        data['reportId'] is! String ||
        (data['reportId'] as String).isEmpty) {
      throw const FormatException('CONTENT_REPORT_FAILED');
    }
  }
}