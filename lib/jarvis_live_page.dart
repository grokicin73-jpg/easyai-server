import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart';
import 'package:dio/dio.dart';

import 'api_service.dart';
import 'credits_page.dart';
import 'jarvis_tasks_page.dart';
import 'instagram_reel_page.dart';
import 'jarvis_video_page.dart';
import 'instagram_products_page.dart';
import 'translations.dart';
import 'ai_content_report.dart';

class JarvisLivePage extends StatefulWidget {
  const JarvisLivePage({
    super.key,
    required this.language,
  });

  final String language;

  @override
  State<JarvisLivePage> createState() => _JarvisLivePageState();
}

class _JarvisLivePageState extends State<JarvisLivePage>
    with WidgetsBindingObserver {
  final _recorder = AudioRecorder();
  final _api = ApiService();

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  StreamSubscription<Uint8List>? _microphoneSubscription;
  Completer<bool>? _ready;

  Future<void> _operations = Future<void>.value();
  Future<void> _audioWork = Future<void>.value();

  int _session = 0;
  int _audioVersion = 0;

  bool _connecting = false;
  bool _connected = false;
  bool _stopping = false;
  bool _speaking = false;
  bool _disposing = false;
  bool _authorizing = false;
  bool _buyingCredits = false;

  Map<String, String> _jarvisHeaders = {};

  String _userText = '';
  String _jarvisText = '';
  String? _error;

  bool _instagramBusy = false;
  bool _instagramChecking = false;
  bool _instagramRefreshPending = false;
  bool _instagramConnected = false;
  bool _instagramStatusKnown = false;
  bool _instagramNeedsReconnect = false;

  String? _instagramUsername;
  String? _instagramError;

  Map<String, String>? _videoDraft;

  bool get _active => mounted && !_disposing;

  bool get _navigationBusy =>
      _stopping ||
      _authorizing ||
      _buyingCredits ||
      _instagramBusy;

  bool _isCurrent(int session) {
    return _active && session == _session;
  }

  String _t(String en, String ky, String ru, String tr) {
    return switch (widget.language) {
      'Кыргызча' => ky,
      'Русский' => ru,
      'Türkçe' => tr,
      _ => en,
    };
  }

  String _connectionError(Object error) {
    final data =
        error is DioException ? error.response?.data : null;

    return _codeMessage(data is Map ? data['code'] : null);
  }

  String _codeMessage(dynamic code) {
    return switch (code) {
      'JARVIS_CREDITS_REQUIRED' => _t(
          'Your free trial has ended. Buy credits to continue.',
          'Акысыз сыноо бүттү. Улантуу үчүн кредит сатып алыңыз.',
          'Пробный период закончился. Купите кредиты для продолжения.',
          'Ücretsiz deneme sona erdi. Devam etmek için kredi satın alın.',
        ),
      'JARVIS_DAILY_LIMIT' => _t(
          'The daily service limit has been reached. Try again tomorrow.',
          'Күндүк чектөө бүттү. Эртең кайра аракет кылыңыз.',
          'Дневной лимит достигнут. Попробуйте завтра.',
          'Günlük hizmet sınırına ulaşıldı. Yarın tekrar deneyin.',
        ),
      'JARVIS_LIVE_ALREADY_ACTIVE' => _t(
          'End your other live conversation first.',
          'Адегенде башка жандуу сүйлөшүүнү токтотуңуз.',
          'Сначала завершите другой живой разговор.',
          'Önce diğer canlı konuşmanızı bitirin.',
        ),
      'JARVIS_DEVICE_ALREADY_LINKED' => _t(
          'This device is linked to another app session. Contact EasyAI support.',
          'Бул түзмөк башка сессияга байланган. EasyAI колдоосуна кайрылыңыз.',
          'Устройство связано с другой сессией. Обратитесь в поддержку EasyAI.',
          'Bu cihaz başka bir oturuma bağlı. EasyAI desteğiyle iletişime geçin.',
        ),
      _ => _t(
          'Could not connect. Check microphone permission and the server.',
          'Улануу мүмкүн болгон жок. Микрофон уруксатын жана серверди текшериңиз.',
          'Не удалось подключиться. Проверьте разрешение на микрофон и сервер.',
          'Bağlantı kurulamadı. Mikrofon iznini ve sunucuyu kontrol edin.',
        ),
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshInstagram());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_active) return;

    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshInstagram());
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_connecting || _connected || _authorizing) {
        unawaited(_stop());
      }
    }
  }

  String? _readUsername(dynamic value) {
    if (value is! String) return null;

    final username =
        value.trim().replaceFirst(RegExp(r'^@'), '');

    return username.isEmpty ? null : username;
  }

  Future<void> _refreshInstagram() async {
    if (!_active) return;

    if (_instagramBusy || _instagramChecking) {
      _instagramRefreshPending = true;
      return;
    }

    setState(() {
      _instagramChecking = true;
      _instagramError = null;
    });

    try {
      final result = await _api.getInstagramStatus();

      if (!_active) return;

      setState(() {
        _instagramConnected = result['connected'] == true;
        _instagramNeedsReconnect =
            result['needsReconnect'] == true;
        _instagramUsername =
            _readUsername(result['username']);
        _instagramStatusKnown = true;
      });
    } catch (_) {
      if (!_active) return;

      setState(() {
        _instagramStatusKnown = false;
        _instagramUsername = null;
        _instagramError = _t(
          'Could not check Instagram. Tap refresh to try again.',
          'Instagram текшерилген жок. Кайра текшериңиз.',
          'Не удалось проверить Instagram. Нажмите обновить.',
          'Instagram kontrol edilemedi. Yenilemeyi deneyin.',
        );
      });
    } finally {
      if (_active) {
        setState(() => _instagramChecking = false);
        _runPendingInstagramRefresh();
      }
    }
  }

  void _runPendingInstagramRefresh() {
    if (!_active ||
        !_instagramRefreshPending ||
        _instagramBusy ||
        _instagramChecking) {
      return;
    }

    _instagramRefreshPending = false;
    unawaited(_refreshInstagram());
  }

  Future<void> _connectInstagram() async {
    if (!_active || _navigationBusy || _instagramChecking) {
      return;
    }

    setState(() {
      _instagramBusy = true;
      _instagramError = null;
    });

    try {
      if (_connecting || _connected) {
        await _stop();
      }

      if (!_active) return;

      await _api.connectInstagram();

      if (!mounted || !_active) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Check the Instagram account in the browser, '
                  'allow access, then return to EasyAI.',
              'Браузерден Instagram аккаунтун текшерип, '
                  'уруксат бериңиз жана EasyAI колдонмосуна кайтыңыз.',
              'Проверьте аккаунт Instagram в браузере, '
                  'разрешите доступ и вернитесь в EasyAI.',
              'Tarayıcıda Instagram hesabını kontrol edin, '
                  'izin verin ve EasyAI uygulamasına dönün.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!_active) return;

      setState(() {
        _instagramError = _t(
          'Could not open Instagram connection. Try again.',
          'Instagram туташуусу ачылган жок. Кайра аракет кылыңыз.',
          'Не удалось открыть подключение Instagram. Попробуйте снова.',
          'Instagram bağlantısı açılamadı. Yeniden deneyin.',
        );
      });
    } finally {
      if (_active) {
        setState(() => _instagramBusy = false);
        _runPendingInstagramRefresh();
      }
    }
  }

  Future<void> _disconnectInstagram() async {
    if (!_active || _navigationBusy || _instagramChecking) {
      return;
    }

    final username = _instagramUsername;
    final account =
        username == null ? '' : '\n\n@$username';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _t(
            'Disconnect Instagram?',
            'Instagram байланышын үзөсүзбү?',
            'Отключить Instagram?',
            'Instagram bağlantısı kesilsin mi?',
          ),
        ),
        content: Text(
          '${_t(
            'Remove this Instagram connection from EasyAI?',
            'Бул Instagram байланышын EasyAI колдонмосунан өчүрөсүзбү?',
            'Удалить это подключение Instagram из EasyAI?',
            'Bu Instagram bağlantısı EasyAI uygulamasından kaldırılsın mı?',
          )}$account',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: Text(
              _t('Cancel', 'Жокко чыгаруу', 'Отмена', 'İptal'),
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: Text(
              _t(
                'Disconnect',
                'Үзүү',
                'Отключить',
                'Bağlantıyı kes',
              ),
            ),
          ),
        ],
      ),
    );

    if (!_active ||
        confirmed != true ||
        _navigationBusy ||
        _instagramChecking) {
      return;
    }

    setState(() {
      _instagramBusy = true;
      _instagramError = null;
    });

    try {
      await _api.disconnectInstagram();

      if (!_active) return;

      setState(() {
        _instagramConnected = false;
        _instagramNeedsReconnect = false;
        _instagramUsername = null;
        _instagramStatusKnown = true;
      });
    } catch (_) {
      if (!_active) return;

      setState(() {
        _instagramError = _t(
          'Could not disconnect Instagram. Try again.',
          'Instagram байланышы үзүлгөн жок. Кайра аракет кылыңыз.',
          'Не удалось отключить Instagram. Попробуйте снова.',
          'Instagram bağlantısı kesilemedi. Yeniden deneyin.',
        );
      });
    } finally {
      if (_active) {
        setState(() => _instagramBusy = false);
        _runPendingInstagramRefresh();
      }
    }
  }

  Future<void> _buyCredits() async {
    if (!_active || _navigationBusy) return;

    setState(() => _buyingCredits = true);

    try {
      await _stop();

      if (!mounted || !_active) return;

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CreditsPage(
            language: widget.language,
          ),
        ),
      );
    } finally {
      if (_active) {
        setState(() => _buyingCredits = false);
      }
    }
  }

  Future<void> _openTasks() async {
    if (!_active || _navigationBusy) return;

    await _stop();

    if (!mounted || !_active) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => JarvisTasksPage(
          language: widget.language,
        ),
      ),
    );
  }

  Future<void> _start() async {
    if (!_active ||
        _connecting ||
        _connected ||
        _navigationBusy) {
      return;
    }

    if (kIsWeb || !Platform.isAndroid) {
      setState(() {
        _error = _t(
          'This mode is available on Android.',
          'Бул режим Android түзмөктөрүндө иштейт.',
          'Этот режим доступен на Android.',
          'Bu mod Android cihazlarda kullanılabilir.',
        );
      });

      return;
    }

    final previousSession = _session;

    setState(() {
      _authorizing = true;
      _error = null;
    });

    try {
      final headers = await _api.getJarvisHeaders(
        language: widget.language,
      );

      if (!_active || previousSession != _session) return;

      _jarvisHeaders = headers;
    } catch (error) {
      if (_active && previousSession == _session) {
        setState(() {
          _error = _connectionError(error);
        });
      }

      return;
    } finally {
      if (_active) {
        setState(() => _authorizing = false);
      }
    }

    if (!_active ||
        previousSession != _session ||
        _stopping) {
      return;
    }

    final session = ++_session;

    setState(() {
      _connecting = true;
      _speaking = false;
      _error = null;
      _userText = '';
      _jarvisText = '';
    });

    _operations = _operations.then((_) => _open(session));
  }

  void _installFeedCallback(int session) {
    FlutterPcmSound.setFeedCallback((remainingFrames) {
      if (!_isCurrent(session) ||
          remainingFrames != 0 ||
          !_speaking) {
        return;
      }

      final pendingAudio = _audioWork;
      final version = _audioVersion;

      unawaited(
        pendingAudio.then<void>((_) async {
          await Future<void>.delayed(
            const Duration(milliseconds: 600),
          );

          if (!_isCurrent(session) ||
              version != _audioVersion ||
              !identical(pendingAudio, _audioWork) ||
              !_speaking) {
            return;
          }

          setState(() => _speaking = false);
        }),
      );
    });
  }

  Future<void> _open(int session) async {
    try {
      if (!_isCurrent(session)) return;

      final permitted = await _recorder.hasPermission();

      if (!_isCurrent(session)) return;

      if (!permitted) {
        throw StateError('Microphone permission denied');
      }

      await FlutterPcmSound.setup(
        sampleRate: 24000,
        channelCount: 1,
      );

      if (!_isCurrent(session)) return;

      await FlutterPcmSound.setFeedThreshold(0);
      _installFeedCallback(session);

      final socket = await WebSocket.connect(
        'wss://easyai-server.onrender.com/api/jarvis/live',
        headers: _jarvisHeaders,
      ).timeout(const Duration(seconds: 30));

      if (!_isCurrent(session)) {
        unawaited(socket.close());
        return;
      }

      socket.pingInterval = const Duration(seconds: 10);
      _socket = socket;

      final ready = Completer<bool>();
      _ready = ready;

      _socketSubscription = socket.listen(
        (data) => _handleMessage(data, session),
        onError: (Object error) {
          if (_isCurrent(session)) {
            unawaited(
              _stop(
                error: _t(
                  'The connection to the server failed.',
                  'Серверге байланыш үзүлдү.',
                  'Соединение с сервером прервано.',
                  'Sunucu bağlantısı kesildi.',
                ),
              ),
            );
          }
        },
        onDone: () {
          if (_isCurrent(session)) {
            unawaited(
              _stop(
                error: _t(
                  'The session ended. Start again.',
                  'Сүйлөшүү аяктады. Кайра баштаңыз.',
                  'Сеанс завершён. Начните снова.',
                  'Oturum sona erdi. Yeniden başlatın.',
                ),
              ),
            );
          }
        },
        cancelOnError: true,
      );

      final accepted = await ready.future.timeout(
        const Duration(seconds: 25),
      );

      if (!_isCurrent(session)) return;

      if (!accepted) {
        throw StateError('Live session not ready');
      }

      final microphone = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          streamBufferSize: 3200,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: false,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceCommunication,
            audioManagerMode: AudioManagerMode.modeInCommunication,
            speakerphone: true,
          ),
        ),
      );

      if (!_isCurrent(session)) return;

      socket.add(jsonEncode({'type': 'start'}));

      setState(() {
        _connecting = false;
        _connected = true;
      });

      _microphoneSubscription = microphone.listen(
        (bytes) {
          if (!_isCurrent(session) ||
              !_connected ||
              _speaking) {
            return;
          }

          final connection = _socket;

          if (connection?.readyState == WebSocket.open) {
            try {
              connection!.add(bytes);
            } catch (_) {
              unawaited(
                _stop(
                  error: _t(
                    'Could not send microphone audio.',
                    'Үн жөнөтүлгөн жок.',
                    'Не удалось отправить звук с микрофона.',
                    'Mikrofon sesi gönderilemedi.',
                  ),
                ),
              );
            }
          }
        },
        onError: (Object error) {
          if (_isCurrent(session)) {
            unawaited(
              _stop(
                error: _t(
                  'The microphone stopped working.',
                  'Микрофон иштебей калды.',
                  'Микрофон перестал работать.',
                  'Mikrofon çalışmayı durdurdu.',
                ),
              ),
            );
          }
        },
        onDone: () {
          if (_isCurrent(session) && _connected) {
            unawaited(
              _stop(
                error: _t(
                  'The microphone stopped. Start again.',
                  'Микрофон токтоду. Кайра баштаңыз.',
                  'Микрофон остановлен. Начните снова.',
                  'Mikrofon durdu. Yeniden başlatın.',
                ),
              ),
            );
          }
        },
        cancelOnError: true,
      );
    } catch (_) {
      if (_isCurrent(session)) {
        unawaited(
          _stop(error: _codeMessage(null)),
        );
      }
    }
  }

  void _handleMessage(dynamic raw, int session) {
    if (!_isCurrent(session)) return;

    try {
      if (raw is! String) {
        throw const FormatException('Expected JSON text');
      }

      final message = jsonDecode(raw);

      if (message is! Map) {
        throw const FormatException('Invalid live message');
      }

      switch (message['type']) {
        case 'videoDraft':
          final title = message['title'];
          final prompt = message['prompt'];
          final caption = message['caption'];

          if (title is! String ||
              title.trim().isEmpty ||
              title.length > 160 ||
              prompt is! String ||
              prompt.trim().isEmpty ||
              prompt.length > 2000 ||
              caption is! String ||
              caption.length > 2200) {
            throw const FormatException('INVALID_VIDEO_DRAFT');
          }

          setState(() {
            _videoDraft = {
              'title': title,
              'prompt': prompt,
              'caption': caption,
            };
          });
          break;

        case 'automationJob':
          setState(() {
            _videoDraft = null;
            _error = _t(
              'Video task started. Its progress is in Tasks.',
              'Видео тапшырмасы башталды. Абалы «Тапшырмалар» бөлүмүндө.',
              'Задача создания видео начата. Статус в разделе «Задачи».',
              'Video görevi başladı. Durum Görevler bölümünde.',
            );
          });
          break;

        case 'businessSettings':
          setState(() {
            _error = _t(
              'Instagram customer reply setting saved.',
              'Instagram кардарларына жооп берүү жөндөөсү сакталды.',
              'Настройка ответов клиентам Instagram сохранена.',
              'Instagram müşteri yanıtı ayarı kaydedildi.',
            );
          });
          break;

        case 'automationError':
          setState(() {
            _error = _t(
              'The action did not start. Check your credits, '
                  'Instagram connection and existing tasks.',
              'Амал башталган жок. Кредитти, Instagram байланышын '
                  'жана тапшырмаларды текшериңиз.',
              'Действие не началось. Проверьте кредиты, '
                  'подключение Instagram и текущие задачи.',
              'İşlem başlamadı. Kredileri, Instagram bağlantısını '
                  've mevcut görevleri kontrol edin.',
            );
          });
          break;

        case 'ready':
          final ready = _ready;

          if (ready != null && !ready.isCompleted) {
            ready.complete(true);
          }
          break;

        case 'audio':
          if (message['data'] is! String ||
              message['rate'] != 24000) {
            throw const FormatException('Invalid audio');
          }

          final bytes = base64Decode(
            message['data'] as String,
          );

          if (bytes.isEmpty || bytes.length.isOdd) return;

          _queueAudio(bytes, session);
          break;

        case 'interrupted':
          _interruptAudio(session);
          break;

        case 'transcript':
          final text = message['text'];

          if (text is! String || text.isEmpty) return;

          setState(() {
            if (message['role'] == 'user') {
              _userText = _appendText(_userText, text);
            } else if (message['role'] == 'model') {
              _jarvisText = _appendText(_jarvisText, text);
            }
          });
          break;

        case 'turnComplete':
          setState(() {
            if (_userText.isNotEmpty) {
              _userText += '\n\n';
            }

            if (_jarvisText.isNotEmpty) {
              _jarvisText += '\n\n';
            }
          });
          break;

        case 'error':
          unawaited(
            _stop(
              error: _codeMessage(message['code']),
            ),
          );
          break;
      }
    } catch (_) {
      unawaited(
        _stop(
          error: _t(
            'Could not process the live response.',
            'Жандуу жоопту окууда ката.',
            'Не удалось обработать ответ.',
            'Canlı yanıt işlenemedi.',
          ),
        ),
      );
    }
  }

  String _appendText(String current, String addition) {
    final result = current + addition;

    if (result.length <= 6000) return result;

    return result.substring(result.length - 6000);
  }

  void _queueAudio(Uint8List bytes, int session) {
    final version = _audioVersion;

    if (!_isCurrent(session)) return;

    if (!_speaking) {
      setState(() => _speaking = true);
    }

    _audioWork = _audioWork.then((_) async {
      if (!_isCurrent(session) ||
          version != _audioVersion) {
        return;
      }

      final data = ByteData.sublistView(bytes);

      final samples = List<int>.generate(
        bytes.length ~/ 2,
        (index) => data.getInt16(index * 2, Endian.little),
        growable: false,
      );

      if (!_speaking) {
        setState(() => _speaking = true);
      }

      await FlutterPcmSound.feed(
        PcmArrayInt16.fromList(samples),
      );
    }).catchError((Object error) {
      if (_isCurrent(session)) {
        unawaited(
          _stop(
            error: _t(
              'Could not play Jarvis audio.',
              'Jarvis үнүн ойнотууда ката.',
              'Не удалось воспроизвести голос Jarvis.',
              'Jarvis sesi oynatılamadı.',
            ),
          ),
        );
      }
    });
  }

  void _interruptAudio(int session) {
    _audioVersion++;

    setState(() => _speaking = false);

    _audioWork = _audioWork.then((_) async {
      if (!_isCurrent(session)) return;

      await FlutterPcmSound.release();

      if (!_isCurrent(session)) return;

      await FlutterPcmSound.setup(
        sampleRate: 24000,
        channelCount: 1,
      );

      if (!_isCurrent(session)) return;

      await FlutterPcmSound.setFeedThreshold(0);
      _installFeedCallback(session);
    }).catchError((Object error) {
      if (_isCurrent(session)) {
        unawaited(
          _stop(
            error: _t(
              'Could not reset audio playback.',
              'Үн байланышын кайра даярдоодо ката.',
              'Не удалось восстановить воспроизведение звука.',
              'Ses oynatma yeniden başlatılamadı.',
            ),
          ),
        );
      }
    });
  }

  Future<void> _stop({String? error}) {
    if (_stopping) return _operations;

    _session++;
    _audioVersion++;

    final ready = _ready;
    _ready = null;

    if (ready != null && !ready.isCompleted) {
      ready.complete(false);
    }

    final socket = _socket;
    _socket = null;

    if (socket != null) {
      unawaited(
        socket.close().catchError((Object _) {}),
      );
    }

    if (_active) {
      setState(() {
        _connecting = false;
        _connected = false;
        _speaking = false;
        _stopping = true;

        if (error != null) {
          _error = error;
        }
      });
    } else {
      _stopping = true;
    }

    _operations = _operations.then((_) async {
      await _cleanup();

      if (_active) {
        setState(() => _stopping = false);
      }
    });

    return _operations;
  }

  Future<void> _cleanup() async {
    final microphone = _microphoneSubscription;
    _microphoneSubscription = null;

    try {
      await microphone?.cancel();
    } catch (_) {}

    try {
      await _recorder.stop();
    } catch (_) {}

    final subscription = _socketSubscription;
    _socketSubscription = null;

    try {
      await subscription?.cancel();
    } catch (_) {}

    try {
      await _audioWork;
    } catch (_) {}

    FlutterPcmSound.setFeedCallback(null);

    try {
      await FlutterPcmSound.release();
    } catch (_) {}
  }

  Future<void> _reportLiveContent() async {
    if (!_active || _navigationBusy) return;

    await _stop();

    if (!mounted || !_active) return;

    final draft = _videoDraft;

    final content = [
      if (_jarvisText.trim().isNotEmpty)
        _jarvisText.trim(),
      if (draft != null) ...[
        draft['title'] ?? '',
        draft['prompt'] ?? '',
        draft['caption'] ?? '',
      ],
    ].where((text) => text.isNotEmpty).join('\n\n');

    await showAIContentReport(
      context: context,
      api: _api,
      language: widget.language,
      contentType: 'voice',
      content: content,
      prompt: _userText,
      model: 'Jarvis Live',
    );
  }

  Future<void> _leave() async {
    await _stop();

    if (!mounted || !_active) return;

    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);

    final stopped = _stop();

    unawaited(
      stopped.then((_) async {
        try {
          await _recorder.dispose();
        } catch (_) {}
      }),
    );

    super.dispose();
  }

  Future<void> _openJarvisVideo() async {
    if (!_active || _navigationBusy) return;

    final draft = _videoDraft;

    if (draft == null) return;

    await _stop();

    if (!mounted || !_active) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => JarvisVideoPage(
          language: widget.language,
          title: draft['title']!,
          prompt: draft['prompt']!,
          caption: draft['caption']!,
        ),
      ),
    );

    if (_active) {
      await _refreshInstagram();
    }
  }

  Future<void> _openInstagramProducts() async {
    if (!_active || _navigationBusy || _instagramChecking) {
      return;
    }

    await _stop();

    if (!mounted || !_active) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InstagramProductsPage(
          language: widget.language,
        ),
      ),
    );

    if (_active) {
      await _refreshInstagram();
    }
  }

  Future<void> _openInstagramReels() async {
    if (!_active || _navigationBusy || _instagramChecking) {
      return;
    }

    await _stop();

    if (!mounted || !_active) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InstagramReelPage(
          language: widget.language,
        ),
      ),
    );

    if (_active) {
      await _refreshInstagram();
    }
  }

  Widget _instagramCard() {
    final busy = _instagramBusy || _instagramChecking;
    final connected =
        _instagramStatusKnown && _instagramConnected;

    final username = _instagramUsername;

    final String status;

    if (_instagramChecking) {
      status = _t(
        'Checking Instagram...',
        'Instagram текшерилүүдө...',
        'Проверяем Instagram...',
        'Instagram kontrol ediliyor...',
      );
    } else if (!_instagramStatusKnown) {
      status = _t(
        'Instagram status unknown',
        'Instagram абалы белгисиз',
        'Статус Instagram неизвестен',
        'Instagram durumu bilinmiyor',
      );
    } else if (_instagramConnected) {
      status = _t(
        'Instagram connected',
        'Instagram туташты',
        'Instagram подключён',
        'Instagram bağlı',
      );
    } else if (_instagramNeedsReconnect) {
      status = _t(
        'Reconnect Instagram',
        'Instagram кайра туташтырылышы керек',
        'Подключите Instagram повторно',
        'Instagram bağlantısını yenileyin',
      );
    } else {
      status = _t(
        'Instagram not connected',
        'Instagram туташкан эмес',
        'Instagram не подключён',
        'Instagram bağlı değil',
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                connected ? Icons.check_circle : Icons.link,
                color: connected
                    ? Colors.greenAccent
                    : Colors.white70,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: _t(
                  'Check connection',
                  'Байланышты текшерүү',
                  'Проверить подключение',
                  'Bağlantıyı kontrol et',
                ),
                onPressed:
                    busy ? null : _refreshInstagram,
                icon: const Icon(Icons.refresh),
                color: Colors.white70,
                disabledColor: Colors.white24,
              ),
            ],
          ),
          if (_instagramStatusKnown &&
              username != null) ...[
            const SizedBox(height: 8),
            Text(
              _t(
                'Connected account',
                'Туташкан аккаунт',
                'Подключённый аккаунт',
                'Bağlı hesap',
              ),
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              '@$username',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (connected && !busy) ...[
              const SizedBox(height: 8),
              Text(
                _t(
                  'Your Reels will be published to @$username.',
                  'Reels видеолоруңуз @$username аккаунтуна жарыяланат.',
                  'Ваши Reels будут опубликованы в аккаунте @$username.',
                  'Reels videolarınız @$username hesabında yayınlanacak.',
                ),
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.4,
                ),
              ),
            ],
          ],
          if (connected &&
              username == null &&
              !busy) ...[
            const SizedBox(height: 8),
            Text(
              _t(
                'The account name is unavailable. Reconnect Instagram '
                    'to verify the account before publishing.',
                'Аккаунттун аты жеткиликсиз. Жарыялоодон мурун '
                    'Instagram кайра туташтырыңыз.',
                'Имя аккаунта недоступно. Подключите Instagram '
                    'повторно перед публикацией.',
                'Hesap adı alınamadı. Yayınlamadan önce '
                    'Instagram bağlantısını yenileyin.',
              ),
              style: const TextStyle(
                color: Colors.orangeAccent,
              ),
            ),
          ],
          if (_instagramError != null) ...[
            const SizedBox(height: 8),
            Text(
              _instagramError!,
              style: const TextStyle(
                color: Colors.orangeAccent,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy || _navigationBusy
                    ? null
                    : _connectInstagram,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.link),
                label: Text(
                  _instagramNeedsReconnect || connected
                      ? _t(
                          'Reconnect Instagram',
                          'Instagram кайра туташтыруу',
                          'Подключить повторно',
                          'Instagram bağlantısını yenile',
                        )
                      : _t(
                          'Connect Instagram',
                          'Instagram туташтыруу',
                          'Подключить Instagram',
                          'Instagram bağla',
                        ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(
                    color: Colors.white54,
                  ),
                ),
              ),
              if (_instagramStatusKnown &&
                  (_instagramConnected ||
                      _instagramNeedsReconnect))
                TextButton(
                  onPressed: busy || _navigationBusy
                      ? null
                      : _disconnectInstagram,
                  child: Text(
                    _t(
                      'Disconnect',
                      'Байланышты үзүү',
                      'Отключить',
                      'Bağlantıyı kes',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _transcript(String title, String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.lightBlueAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            text.trim(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _stopping
        ? _t(
            'Stopping...',
            'Токтотулууда...',
            'Завершение...',
            'Sonlandırılıyor...',
          )
        : _connecting || _authorizing
            ? _t(
                'Connecting...',
                'Уланууда...',
                'Подключение...',
                'Bağlanıyor...',
              )
            : _connected
                ? _speaking
                    ? _t(
                        'Jarvis is speaking',
                        'Jarvis сүйлөп жатат',
                        'Jarvis говорит',
                        'Jarvis konuşuyor',
                      )
                    : _t(
                        'Listening. Go ahead.',
                        'Угуп жатам. Сүйлөй бериңиз.',
                        'Слушаю. Говорите.',
                        'Dinliyorum. Konuşabilirsiniz.',
                      )
                : _t(
                    'Start a conversation',
                    'Сүйлөшүүнү баштаңыз',
                    'Начните разговор',
                    'Bir konuşma başlatın',
                  );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_leave());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Jarvis Live'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _stopping ? null : _leave,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.assignment_outlined),
              onPressed:
                  _navigationBusy ? null : _openTasks,
            ),
            IconButton(
              tooltip: AppTranslations.translate(
                widget.language,
                'aiReportButton',
              ),
              icon: const Icon(Icons.flag_outlined),
              onPressed:
                  _navigationBusy ? null : _reportLiveContent,
            ),
            IconButton(
              tooltip: _t(
                'My products',
                'Менин товарларым',
                'Мои товары',
                'Ürünlerim',
              ),
              icon: const Icon(Icons.storefront_outlined),
              onPressed:
                  _navigationBusy || _instagramChecking
                      ? null
                      : _openInstagramProducts,
            ),
            IconButton(
              tooltip: _t(
                'Publish Reels',
                'Reels жарыялоо',
                'Опубликовать Reels',
                'Reels yayınla',
              ),
              icon: const Icon(Icons.video_library_outlined),
              onPressed:
                  _navigationBusy || _instagramChecking
                      ? null
                      : _openInstagramReels,
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        Icon(
                          _speaking
                              ? Icons.graphic_eq
                              : Icons.mic,
                          size: 80,
                          color: _connected
                              ? Colors.lightBlueAccent
                              : Colors.white54,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _t(
                            '1 free minute once per device. '
                                'Then 1 credit for each started minute. '
                                'Maximum session: 15 minutes.',
                            'Ар бир түзмөккө бир жолу 1 акысыз мүнөт. '
                                'Андан кийин ар бир башталган мүнөт 1 кредит. '
                                'Бир сессия 15 мүнөткө чейин.',
                            'Один раз на устройство: 1 бесплатная минута. '
                                'Затем 1 кредит за каждую начатую минуту. '
                                'Сеанс до 15 минут.',
                            'Cihaz başına bir kez 1 ücretsiz dakika. '
                                'Ardından başlanan her dakika için 1 kredi. '
                                'Oturum en fazla 15 dakika.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white60,
                          ),
                        ),
                        TextButton(
                          onPressed: _navigationBusy
                              ? null
                              : _buyCredits,
                          child: Text(
                            AppTranslations.translate(
                              widget.language,
                              'buyCredits',
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _instagramCard(),
                        const SizedBox(height: 20),
                        if (_videoDraft != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF202020),
                              borderRadius:
                                  BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white24,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _t(
                                    'Jarvis prepared a video draft',
                                    'Jarvis видео таслагын даярдады',
                                    'Jarvis подготовил черновик видео',
                                    'Jarvis bir video taslağı hazırladı',
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _videoDraft!['title']!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _navigationBusy
                                      ? null
                                      : _openJarvisVideo,
                                  icon: const Icon(
                                    Icons.movie_creation_outlined,
                                  ),
                                  label: Text(
                                    _t(
                                      'Review video draft',
                                      'Видео таслагын текшерүү',
                                      'Посмотреть черновик видео',
                                      'Video taslağını incele',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (_userText.trim().isNotEmpty)
                          _transcript(
                            _t('You', 'Сиз', 'Вы', 'Siz'),
                            _userText,
                          ),
                        if (_jarvisText.trim().isNotEmpty)
                          _transcript('Jarvis', _jarvisText),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: 12,
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _navigationBusy
                        ? null
                        : _connected || _connecting
                            ? () => unawaited(_stop())
                            : _start,
                    icon: Icon(
                      _connected || _connecting
                          ? Icons.call_end
                          : Icons.call,
                    ),
                    label: Text(
                      _connected || _connecting
                          ? _t(
                              'End conversation',
                              'Токтотуу',
                              'Завершить разговор',
                              'Konuşmayı bitir',
                            )
                          : _t(
                              'Start conversation',
                              'Баштоо',
                              'Начать разговор',
                              'Konuşmayı başlat',
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}