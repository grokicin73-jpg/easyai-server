import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

import 'jarvis_live_page.dart';
import 'api_service.dart';
import 'credits_page.dart';
import 'jarvis_tasks_page.dart';
import 'translations.dart';
import 'ai_content_report.dart';

class JarvisPage extends StatefulWidget {
  const JarvisPage({
    super.key,
    required this.language,
  });

  final String language;

  @override
  State<JarvisPage> createState() => _JarvisPageState();
}

class _JarvisPageState extends State<JarvisPage> {
  final _controller = TextEditingController();
  final _api = ApiService();
  final _scrollController = ScrollController();
  final _recorder = AudioRecorder();
  final _voicePlayer = AudioPlayer();

  final _dio = Dio(
    BaseOptions(
      baseUrl: 'https://easyai-server.onrender.com',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 90),
    ),
  );

  final List<Map<String, String>> _messages = [];
  final List<Map<String, String>> _history = [];

  CancelToken? _cancelToken;
  CancelToken? _speechCancelToken;

  Timer? _recordTimer;

  String? _recordPath;
  String? _speechPath;

  int _speechVersion = 0;

  bool _authorized = false;
  bool _preparing = true;
  bool _isSending = false;
  bool _isBuying = false;
  bool _isRecording = false;
  bool _isTranscribing = false;
  bool _isRecorderBusy = false;

  String? _error;
  String? _pendingRequestId;
  String? _pendingMessage;

  bool get _busy =>
      _preparing ||
      _isSending ||
      _isBuying ||
      _isTranscribing ||
      _isRecorderBusy;

  String _t(String en, String ky, String ru, String tr) {
    return switch (widget.language) {
      'Кыргызча' => ky,
      'Русский' => ru,
      'Türkçe' => tr,
      _ => en,
    };
  }

  String _requestError(Object error, String fallback) {
    final data =
        error is DioException ? error.response?.data : null;

    final code = data is Map ? data['code'] : null;

    final status =
        error is DioException ? error.response?.statusCode : null;

    if (status == 401) {
      _authorized = false;
    }

    return switch (code) {
      'FREE_LIMIT_REACHED' || 'JARVIS_CREDITS_REQUIRED' => _t(
          'Your free trial has ended. Buy credits to continue.',
          'Акысыз сыноо бүттү. Улантуу үчүн кредит сатып алыңыз.',
          'Пробный период закончился. Купите кредиты для продолжения.',
          'Ücretsiz deneme sona erdi. Devam etmek için kredi satın alın.',
        ),
      'AUTOMATION_ALREADY_ACTIVE' => _t(
          'A video task is already active. Check Tasks first.',
          'Видео тапшырмасы аткарылууда. Адегенде «Тапшырмалар» бөлүмүн текшериңиз.',
          'Задача видео уже выполняется. Сначала проверьте «Задачи».',
          'Bir video görevi zaten çalışıyor. Önce Görevler’i kontrol edin.',
        ),
      'INSTAGRAM_RECONNECT_REQUIRED' ||
      'INSTAGRAM_PUBLISH_PERMISSION_REQUIRED' ||
      'INSTAGRAM_MESSAGING_PERMISSION_REQUIRED' =>
        _t(
          'Reconnect Instagram and allow the required permissions.',
          'Instagramды кайра туташтырып, керектүү уруксаттарды бериңиз.',
          'Подключите Instagram заново и предоставьте нужные разрешения.',
          'Instagram’ı yeniden bağlayıp gerekli izinleri verin.',
        ),
      'JARVIS_DEVICE_ALREADY_LINKED' => _t(
          'This device is linked to another app session. Contact EasyAI support.',
          'Бул түзмөк башка сессияга байланган. EasyAI колдоосуна кайрылыңыз.',
          'Устройство связано с другой сессией. Обратитесь в поддержку EasyAI.',
          'Bu cihaz başka bir oturuma bağlı. EasyAI desteğiyle iletişime geçin.',
        ),
      'JARVIS_DAILY_LIMIT' => _t(
          'The daily service limit has been reached. Try again tomorrow.',
          'Күндүк чектөө бүттү. Эртең кайра аракет кылыңыз.',
          'Дневной лимит достигнут. Попробуйте завтра.',
          'Günlük hizmet sınırına ulaşıldı. Yarın tekrar deneyin.',
        ),
      'JARVIS_REQUEST_ALREADY_USED' ||
      'JARVIS_REQUEST_CONFLICT' =>
        _t(
          'This request has already been processed. Please try again.',
          'Бул сурам мурда иштетилген. Кайра аракет кылыңыз.',
          'Этот запрос уже обработан. Попробуйте снова.',
          'Bu istek daha önce işlendi. Yeniden deneyin.',
        ),
      _ => status == 429 || status == 503
          ? _t(
              'AI is busy. Please try again shortly.',
              'AI бош эмес. Бир аздан кийин кайра аракет кылыңыз.',
              'ИИ занят. Попробуйте немного позже.',
              'Yapay zekâ meşgul. Biraz sonra tekrar deneyin.',
            )
          : fallback,
    };
  }

  @override
  void initState() {
    super.initState();
    unawaited(_initializeSession());
  }

  Future<void> _ensureSession() async {
    if (_authorized) return;

    if (kIsWeb || !Platform.isAndroid) {
      throw StateError('JARVIS_ANDROID_REQUIRED');
    }

    final headers = await _api.getJarvisHeaders(
      language: widget.language,
    );

    if (!mounted) return;

    _dio.options.headers.addAll(headers);
    _authorized = true;
  }

  Future<void> _initializeSession() async {
    try {
      await _ensureSession();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = _requestError(
          error,
          _t(
            'Could not connect to Jarvis. Try sending your message again.',
            'Jarvis туташкан жок. Билдирүүнү кайра жөнөтүңүз.',
            'Не удалось подключить Jarvis. Попробуйте отправить сообщение снова.',
            'Jarvis bağlantısı kurulamadı. Mesajınızı yeniden göndermeyi deneyin.',
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _preparing = false);
      }
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  Future<void> _deleteFile(String? path) async {
    if (path == null) return;

    try {
      final file = File(path);

      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _stopSpeech() async {
    _speechVersion++;

    _speechCancelToken?.cancel();
    _speechCancelToken = null;

    final path = _speechPath;
    _speechPath = null;

    try {
      await _voicePlayer.stop();
    } catch (_) {}

    await _deleteFile(path);
  }

  Future<void> _speakReply(
    String reply,
    String requestId,
    String speechToken,
  ) async {
    if (!mounted || kIsWeb || !Platform.isAndroid) return;

    await _stopSpeech();

    if (!mounted || _isRecording || _isRecorderBusy) return;

    final version = _speechVersion;
    final token = CancelToken();

    _speechCancelToken = token;

    String? localPath;
    bool started = false;

    try {
      final response = await _dio.post<List<int>>(
        '/api/jarvis/speak',
        data: {
          'text': reply,
          'requestId': requestId,
          'speechToken': speechToken,
        },
        options: Options(
          responseType: ResponseType.bytes,
        ),
        cancelToken: token,
      );

      if (!mounted || version != _speechVersion) return;

      final bytes = response.data;

      if (bytes == null || bytes.length < 44) {
        throw StateError('Empty speech response');
      }

      final directory = await getTemporaryDirectory();

      if (!mounted || version != _speechVersion) return;

      localPath =
          '${directory.path}/jarvis_reply_${DateTime.now().microsecondsSinceEpoch}.wav';

      await File(localPath).writeAsBytes(
        bytes,
        flush: true,
      );

      if (!mounted || version != _speechVersion) return;

      _speechPath = localPath;

      await _voicePlayer.play(
        DeviceFileSource(localPath),
      );

      if (!mounted || version != _speechVersion) return;

      started = true;
    } catch (error) {
      if (!mounted || version != _speechVersion) return;

      if (error is DioException && CancelToken.isCancel(error)) {
        return;
      }

      setState(() {
        _error = _t(
          'The reply is ready, but audio could not be played.',
          'Жооп даяр, бирок үн ойнотулган жок.',
          'Ответ готов, но не удалось воспроизвести звук.',
          'Yanıt hazır, ancak ses oynatılamadı.',
        );
      });
    } finally {
      if (!started) {
        await _deleteFile(localPath);

        if (_speechPath == localPath) {
          _speechPath = null;
        }
      }

      if (identical(_speechCancelToken, token)) {
        _speechCancelToken = null;
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_busy) return;

    if (kIsWeb || !Platform.isAndroid) {
      setState(() {
        _error = _t(
          'Voice input is available on Android.',
          'Үн киргизүү Android түзмөктөрүндө иштейт.',
          'Голосовой ввод доступен на Android.',
          'Sesli giriş Android cihazlarda kullanılabilir.',
        );
      });

      return;
    }

    if (!_isRecording &&
        _controller.text.trim().isNotEmpty) {
      setState(() {
        _error = _t(
          'Send or clear your typed message first.',
          'Адегенде жазылган билдирүүнү жөнөтүңүз же тазалаңыз.',
          'Сначала отправьте или очистите написанное сообщение.',
          'Önce yazdığınız mesajı gönderin veya temizleyin.',
        );
      });

      return;
    }

    final wasRecording = _isRecording;

    setState(() {
      _isRecorderBusy = true;
      _error = null;
    });

    try {
      if (!wasRecording) {
        await _ensureSession();

        if (!mounted) return;

        await _stopSpeech();

        if (!mounted) return;

        final permitted = await _recorder.hasPermission();

        if (!mounted) return;

        if (!permitted) {
          setState(() {
            _error = _t(
              'Please allow microphone access.',
              'Микрофонго уруксат бериңиз.',
              'Разрешите доступ к микрофону.',
              'Lütfen mikrofon erişimine izin verin.',
            );
          });

          return;
        }

        final directory = await getTemporaryDirectory();

        if (!mounted) return;

        _recordPath =
            '${directory.path}/jarvis_${DateTime.now().microsecondsSinceEpoch}.wav';

        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: _recordPath!,
        );

        if (!mounted) {
          await _recorder.cancel();
          return;
        }

        setState(() => _isRecording = true);

        _recordTimer = Timer(
          const Duration(seconds: 30),
          () {
            if (mounted && _isRecording) {
              unawaited(_toggleRecording());
            }
          },
        );
      } else {
        _recordTimer?.cancel();
        _recordTimer = null;

        final path = await _recorder.stop();

        if (!mounted) return;

        setState(() {
          _isRecording = false;
          _isTranscribing = true;
        });

        if (path == null) {
          throw StateError('No recording file');
        }

        final bytes = await File(path).readAsBytes();

        if (!mounted) return;

        if (bytes.length <= 44 ||
            bytes.length > 2 * 1024 * 1024) {
          throw StateError('Invalid recording size');
        }

        await _ensureSession();

        if (!mounted) return;

        final token = CancelToken();
        _cancelToken = token;

        final response = await _dio.post(
          '/api/jarvis/transcribe',
          data: FormData.fromMap({
            'audio': MultipartFile.fromBytes(
              bytes,
              filename: 'voice.wav',
            ),
          }),
          cancelToken: token,
        );

        if (!mounted) return;

        final data = response.data;

        if (data is! Map ||
            data['success'] != true ||
            data['transcript'] is! String) {
          throw StateError('Invalid transcription');
        }

        final text =
            (data['transcript'] as String).trim();

        if (text.isEmpty || text.length > 2000) {
          throw StateError('Invalid transcript length');
        }

        setState(() {
          _controller.text = text;
          _controller.selection =
              TextSelection.collapsed(offset: text.length);
        });
      }
    } catch (error) {
      _recordTimer?.cancel();
      _recordTimer = null;

      try {
        await _recorder.cancel();
      } catch (_) {}

      if (!mounted) return;

      if (error is DioException && CancelToken.isCancel(error)) {
        return;
      }

      setState(() {
        _isRecording = false;

        _error = _requestError(
          error,
          _t(
            'Could not process the recording. Please try again.',
            'Үн алынган жок. Кайра аракет кылыңыз.',
            'Не удалось обработать запись. Попробуйте ещё раз.',
            'Kayıt işlenemedi. Lütfen tekrar deneyin.',
          ),
        );
      });
    } finally {
      if (wasRecording || !mounted || !_isRecording) {
        final path = _recordPath;
        _recordPath = null;

        await _deleteFile(path);
      }

      if (mounted) {
        setState(() {
          _isRecorderBusy = false;
          _isTranscribing = false;
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final message = _controller.text.trim();

    if (_busy ||
        _isRecording ||
        message.isEmpty ||
        message.length > 2000) {
      return;
    }

    FocusScope.of(context).unfocus();

    final token = CancelToken();
    _cancelToken = token;

    final userMessage = <String, String>{
      'role': 'user',
      'text': message,
    };

    setState(() {
      _isSending = true;
      _error = null;
      _messages.add(userMessage);
      _controller.clear();
    });

    _scrollDown();

    try {
      await _ensureSession();

      if (!mounted) return;

      if (_pendingMessage != message) {
        _pendingRequestId = _api.createJarvisRequestId();
        _pendingMessage = message;
      }

      final requestId = _pendingRequestId!;

      final response = await _dio.post(
        '/api/jarvis/chat',
        data: {
          'requestId': requestId,
          'message': message,
          'history': List<Map<String, String>>.from(
            _history,
          ),
        },
        cancelToken: token,
      );

      if (!mounted) return;

      final data = response.data;

      if (data is! Map ||
          data['success'] != true ||
          data['reply'] is! String) {
        throw StateError('Invalid Jarvis response');
      }

      final reply = (data['reply'] as String).trim();

      if (reply.isEmpty) {
        throw StateError('Empty Jarvis response');
      }

      setState(() {
        _messages.add({
          'role': 'model',
          'text': reply,
          'prompt': message,
        });

        _history.add({
          'role': 'user',
          'text': message,
        });

        _history.add({
          'role': 'model',
          'text': reply.length > 2000
              ? reply.substring(0, 2000)
              : reply,
        });

        while (_history.length > 6) {
          _history.removeRange(0, 2);
        }
      });

      _pendingRequestId = null;
      _pendingMessage = null;

      _scrollDown();

      final speechToken = data['speechToken'];

      if (speechToken is String &&
          speechToken.isNotEmpty) {
        unawaited(
          _speakReply(
            reply,
            requestId,
            speechToken,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;

      if (error is DioException && CancelToken.isCancel(error)) {
        return;
      }

      final errorData =
          error is DioException ? error.response?.data : null;

      final errorCode =
          errorData is Map ? errorData['code'] : null;

      final definitiveActionFailure = {
        'FREE_LIMIT_REACHED',
        'AUTOMATION_ALREADY_ACTIVE',
        'AUTOMATION_DAILY_LIMIT',
        'INSTAGRAM_RECONNECT_REQUIRED',
        'INSTAGRAM_PUBLISH_PERMISSION_REQUIRED',
        'INSTAGRAM_MESSAGING_PERMISSION_REQUIRED',
      }.contains(errorCode);

      if (error is DioException &&
          error.response != null &&
          (error.response?.statusCode != 409 ||
              definitiveActionFailure)) {
        _pendingRequestId = null;
        _pendingMessage = null;
      }

      setState(() {
        _messages.remove(userMessage);
        _controller.text = message;

        _controller.selection =
            TextSelection.collapsed(offset: message.length);

        _error = _requestError(
          error,
          _t(
            'Could not get a reply. Please try again.',
            'Жооп алынган жок. Кайра аракет кылыңыз.',
            'Не удалось получить ответ. Попробуйте ещё раз.',
            'Yanıt alınamadı. Lütfen tekrar deneyin.',
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _buyCredits() async {
    if (_busy || _isRecording) return;

    setState(() => _isBuying = true);

    try {
      await _stopSpeech();

      if (!mounted) return;

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CreditsPage(
            language: widget.language,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBuying = false);
      }
    }
  }

  Future<void> _openTasks() async {
    if (_busy || _isRecording) return;

    await _stopSpeech();

    if (!mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => JarvisTasksPage(
          language: widget.language,
        ),
      ),
    );
  }

  Future<void> _openLive() async {
    if (_busy || _isRecording) return;

    await _stopSpeech();

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => JarvisLivePage(
          language: widget.language,
        ),
      ),
    );
  }

  Future<void> _reportMessage(
    Map<String, String> message,
  ) async {
    await _stopSpeech();

    if (!mounted) return;

    await showAIContentReport(
      context: context,
      api: _api,
      language: widget.language,
      contentType: 'chat',
      content: message['text'] ?? '',
      prompt: message['prompt'] ?? '',
      model: 'Jarvis',
    );
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _cancelToken?.cancel();

    _speechVersion++;
    _speechCancelToken?.cancel();

    _dio.close(force: true);

    final recordPath = _recordPath;
    final speechPath = _speechPath;

    unawaited(() async {
      try {
        await _voicePlayer.dispose();
      } catch (_) {}

      try {
        await _recorder.cancel();
      } catch (_) {}

      try {
        await _recorder.dispose();
      } catch (_) {}

      await _deleteFile(recordPath);
      await _deleteFile(speechPath);
    }());

    _controller.dispose();
    _scrollController.dispose();

    super.dispose();
  }

  Widget _messageBubble(Map<String, String> message) {
    final isUser = message['role'] == 'user';

    return Align(
      alignment:
          isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF12364A)
              : const Color(0xFF202020),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? _t('You', 'Сиз', 'Вы', 'Siz') : 'Jarvis',
              style: const TextStyle(
                color: Colors.lightBlueAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              message['text'] ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.4,
              ),
            ),
            if (!isUser) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.flag_outlined),
                label: Text(
                  AppTranslations.translate(
                    widget.language,
                    'aiReportButton',
                  ),
                ),
                onPressed: _busy || _isRecording
                    ? null
                    : () => _reportMessage(message),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _preparing
        ? _t(
            'Connecting...',
            'Уланууда...',
            'Подключение...',
            'Bağlanıyor...',
          )
        : _isBuying
            ? _t(
                'Opening purchases...',
                'Сатып алуу ачылууда...',
                'Открываем покупки...',
                'Satın alma ekranı açılıyor...',
              )
            : _t(
                'Jarvis is replying...',
                'Jarvis жооп даярдоодо...',
                'Jarvis готовит ответ...',
                'Jarvis yanıt hazırlıyor...',
              );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Jarvis'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment_outlined),
            onPressed: _busy || _isRecording
                ? null
                : _openTasks,
          ),
          IconButton(
            tooltip: _t(
              'Live conversation',
              'Жандуу сүйлөшүү',
              'Живой разговор',
              'Canlı sohbet',
            ),
            icon: const Icon(
              Icons.headset_mic,
              color: Colors.lightBlueAccent,
            ),
            onPressed: _busy || _isRecording
                ? null
                : _openLive,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                _t(
                  '3 free replies once per device. Then 1 credit per reply; reading the reply aloud is included.',
                  'Ар бир түзмөккө бир жолу 3 акысыз жооп. Андан кийин ар бир жооп 1 кредит; үн менен окуу кошулган.',
                  'Один раз на устройство: 3 бесплатных ответа. Затем 1 кредит за ответ; озвучивание включено.',
                  'Cihaz başına bir kez 3 ücretsiz yanıt. Ardından yanıt başına 1 kredi; seslendirme dahil.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                ),
              ),
              TextButton(
                onPressed: _busy || _isRecording
                    ? null
                    : _buyCredits,
                child: Text(
                  AppTranslations.translate(
                    widget.language,
                    'buyCredits',
                  ),
                ),
              ),
              Expanded(
                child: _messages.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                size: 64,
                                color: Colors.lightBlueAccent,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                _t(
                                  'Your video assistant',
                                  'Сиздин видео жардамчыңыз',
                                  'Ваш видеопомощник',
                                  'Video asistanınız',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _t(
                                  'Write in your own language.\n'
                                      'Let’s develop your video idea together.',
                                  'Өз тилиңизде жазыңыз.\n'
                                      'Видео идеяңызды чогуу даярдайбыз.',
                                  'Пишите на своём языке.\n'
                                      'Давайте вместе разработаем идею вашего видео.',
                                  'Kendi dilinizde yazın.\n'
                                      'Video fikrinizi birlikte geliştirelim.',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _messages.length,
                        itemBuilder: (_, index) =>
                            _messageBubble(_messages[index]),
                      ),
              ),
              if (_preparing || _isSending || _isBuying)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.lightBlueAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(progress)),
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_busy && !_isRecording,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        color: Colors.white,
                      ),
                      decoration: InputDecoration(
                        hintText: _isRecording
                            ? _t(
                                'Listening...',
                                'Угуп жатам...',
                                'Слушаю...',
                                'Dinliyorum...',
                              )
                            : _t(
                                'Write a message...',
                                'Билдирүү жазыңыз...',
                                'Напишите сообщение...',
                                'Bir mesaj yazın...',
                              ),
                        hintStyle: const TextStyle(
                          color: Colors.white54,
                        ),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: _isRecording
                        ? _t(
                            'Stop recording',
                            'Жазууну токтотуу',
                            'Остановить запись',
                            'Kaydı durdur',
                          )
                        : _t(
                            'Record voice',
                            'Үн жазуу',
                            'Записать голос',
                            'Ses kaydet',
                          ),
                    onPressed:
                        _busy ? null : _toggleRecording,
                    icon: _isTranscribing || _isRecorderBusy
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.lightBlueAccent,
                            ),
                          )
                        : Icon(
                            _isRecording
                                ? Icons.stop_circle
                                : Icons.mic,
                            color: _isRecording
                                ? Colors.redAccent
                                : Colors.lightBlueAccent,
                            size: 32,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _busy ||
                          _isRecording ||
                          _controller.text.trim().isEmpty
                      ? null
                      : _sendMessage,
                  child: Text(
                    _t(
                      'Send',
                      'Жөнөтүү',
                      'Отправить',
                      'Gönder',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}