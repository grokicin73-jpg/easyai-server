import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'translations.dart';
import 'ai_content_report.dart';

class InstagramReelPage extends StatefulWidget {
  final String language;
  final String initialVideoUrl;
  final String initialCaption;

  const InstagramReelPage({
    super.key,
    required this.language,
    this.initialVideoUrl = '',
    this.initialCaption = '',
  });

  @override
  State<InstagramReelPage> createState() => _InstagramReelPageState();
}

class _InstagramReelPageState extends State<InstagramReelPage> {
  static const _storage = FlutterSecureStorage();
  static const _draftKey = 'easyai_instagram_reel_draft_v1';

  // English, Кыргызча, Русский, Türkçe.
  static const Map<String, List<String>> _texts = {
    'help': [
      'Choose a video or enter its EasyAI URL. Preview it before publishing.',
      'Видео тандаңыз же анын EasyAI шилтемесин киргизиңиз. Жарыялоодон мурун көрүңүз.',
      'Выберите видео или введите его ссылку EasyAI. Просмотрите перед публикацией.',
      'Video seçin veya EasyAI bağlantısını girin. Yayınlamadan önce izleyin.',
    ],
    'choose': [
      'Choose video from gallery',
      'Галереядан видео тандоо',
      'Выбрать видео из галереи',
      'Galeriden video seç',
    ],
    'url': [
      'MP4 video URL',
      'MP4 видеонун шилтемеси',
      'Ссылка на MP4-видео',
      'MP4 video bağlantısı',
    ],
    'caption': [
      'Caption and hashtags',
      'Сүрөттөмө жана хештегдер',
      'Описание и хештеги',
      'Açıklama ve etiketler',
    ],
    'preview': [
      'Preview video',
      'Видеону көрүү',
      'Посмотреть видео',
      'Videoyu izle',
    ],
    'prepare': [
      'Prepare video',
      'Видеону даярдоо',
      'Подготовить видео',
      'Videoyu hazırla',
    ],
    'continue': [
      'Continue preparation',
      'Даярдоону улантуу',
      'Продолжить подготовку',
      'Hazırlamaya devam et',
    ],
    'check': [
      'Check status',
      'Абалын текшерүү',
      'Проверить статус',
      'Durumu kontrol et',
    ],
    'publish': [
      'Publish to Instagram',
      'Instagramга жарыялоо',
      'Опубликовать в Instagram',
      'Instagram’da yayınla',
    ],
    'new': [
      'New video',
      'Жаңы видео',
      'Новое видео',
      'Yeni video',
    ],
    'restart': [
      'Restart preparation',
      'Даярдоону кайра баштоо',
      'Начать подготовку заново',
      'Hazırlamayı yeniden başlat',
    ],
    'restartTitle': [
      'Restart this draft?',
      'Бул видеону кайра даярдайсызбы?',
      'Подготовить этот черновик заново?',
      'Bu taslak yeniden hazırlansın mı?',
    ],
    'restartBody': [
      'The server will check the old request first. The video URL and caption will be kept. This button does not publish a video.',
      'Сервер адегенде эски сурамды текшерет. Видеонун шилтемеси жана сүрөттөмөсү сакталат. Бул баскыч видеону жарыялабайт.',
      'Сервер сначала проверит старый запрос. Ссылка и описание сохранятся. Эта кнопка не публикует видео.',
      'Sunucu önce eski isteği kontrol edecek. Video bağlantısı ve açıklaması korunacak. Bu düğme video yayınlamaz.',
    ],
    'confirmTitle': [
      'Publish to Instagram?',
      'Instagramга жарыялайсызбы?',
      'Опубликовать в Instagram?',
      'Instagram’da yayınlansın mı?',
    ],
    'confirmBody': [
      'Publish this video and caption to the Reels tab and feed of your connected Instagram account?',
      'Бул видеону жана сүрөттөмөнү туташкан Instagram аккаунтуңуздун Reels бөлүмүнө жана тасмасына жарыялайсызбы?',
      'Опубликовать это видео и описание в Reels и ленте подключённого аккаунта Instagram?',
      'Bu video ve açıklama, bağlı Instagram hesabınızın Reels sekmesinde ve akışında yayınlansın mı?',
    ],
    'cancel': [
      'Cancel',
      'Жокко чыгаруу',
      'Отмена',
      'İptal',
    ],
    'noCaption': [
      '(No caption)',
      '(Сүрөттөмөсүз)',
      '(Без описания)',
      '(Açıklama yok)',
    ],
    'intro': [
      'Choose a video and add a caption.',
      'Видео тандап, сүрөттөмө кошуңуз.',
      'Выберите видео и добавьте описание.',
      'Video seçip açıklama ekleyin.',
    ],
    'saved': [
      'Your draft was restored. Check its status.',
      'Сакталган видео ачылды. Абалын текшериңиз.',
      'Черновик восстановлен. Проверьте статус.',
      'Taslağınız açıldı. Durumunu kontrol edin.',
    ],
    'unknown': [
      'The previous preparation result is unknown. You can restart preparation below. Publishing remains unavailable.',
      'Мурунку даярдоонун натыйжасы белгисиз. Төмөнкү баскыч менен кайра баштасаңыз болот. Жарыялоо азырынча жеткиликсиз.',
      'Результат предыдущей подготовки неизвестен. Можно начать подготовку заново кнопкой ниже. Публикация пока недоступна.',
      'Önceki hazırlamanın sonucu bilinmiyor. Aşağıdaki düğmeyle yeniden başlayabilirsiniz. Yayınlama henüz kullanılamıyor.',
    ],
    'resetDone': [
      'Draft unlocked. Preview the video, then tap Prepare video.',
      'Видео ачылды. Көрүп, анан «Видеону даярдоо» баскычын басыңыз.',
      'Черновик разблокирован. Просмотрите видео и нажмите «Подготовить видео».',
      'Taslak açıldı. Videoyu izleyin ve “Videoyu hazırla” düğmesine dokunun.',
    ],
    'resetBlocked': [
      'The server has not confirmed that this draft can be restarted. Check its status.',
      'Сервер кайра баштоого болорун ырастаган жок. Абалын текшериңиз.',
      'Сервер не подтвердил возможность начать заново. Проверьте статус.',
      'Sunucu yeniden başlatılabileceğini doğrulamadı. Durumunu kontrol edin.',
    ],
    'storage': [
      'Could not read or save the draft. Close this page and open it again.',
      'Маалымат ачылган же сакталган жок. Баракты жаап, кайра ачыңыз.',
      'Не удалось прочитать или сохранить черновик. Закройте страницу и откройте снова.',
      'Taslak okunamadı veya kaydedilemedi. Sayfayı kapatıp yeniden açın.',
    ],
    'selecting': [
      'Choose an MP4 video.',
      'MP4 видео тандаңыз.',
      'Выберите MP4-видео.',
      'Bir MP4 video seçin.',
    ],
    'uploading': [
      'Uploading video. Keep this page open...',
      'Видео жүктөлүүдө. Баракты жаппаңыз...',
      'Видео загружается. Не закрывайте страницу...',
      'Video yükleniyor. Sayfayı açık tutun...',
    ],
    'uploaded': [
      'Video uploaded. Preview it and prepare it.',
      'Видео жүктөлдү. Көрүп, анан даярдаңыз.',
      'Видео загружено. Просмотрите и подготовьте.',
      'Video yüklendi. İzleyin ve hazırlayın.',
    ],
    'large': [
      'Choose a video no larger than 100 MB.',
      '100 МБдан ашпаган видео тандаңыз.',
      'Выберите видео не больше 100 МБ.',
      'En fazla 100 MB video seçin.',
    ],
    'mp4': [
      'Choose a supported MP4 video.',
      'Колдоого алынган MP4 видео тандаңыз.',
      'Выберите поддерживаемое MP4-видео.',
      'Desteklenen bir MP4 video seçin.',
    ],
    'uploadBusy': [
      'Another upload is in progress. Wait and try again.',
      'Башка видео жүктөлүүдө. Күтүп, кайра аракет кылыңыз.',
      'Другое видео загружается. Подождите и повторите.',
      'Başka bir video yükleniyor. Bekleyip tekrar deneyin.',
    ],
    'uploadFailed': [
      'Video upload failed. Check your connection.',
      'Видео жүктөлгөн жок. Байланышты текшериңиз.',
      'Видео не загрузилось. Проверьте соединение.',
      'Video yüklenemedi. Bağlantınızı kontrol edin.',
    ],
    'invalidUrl': [
      'Enter an MP4 video URL from the EasyAI server.',
      'EasyAI сервериндеги MP4 видеонун шилтемесин киргизиңиз.',
      'Введите ссылку на MP4-видео с сервера EasyAI.',
      'EasyAI sunucusundaki bir MP4 video bağlantısını girin.',
    ],
    'captionLong': [
      'The caption must not exceed 2200 characters.',
      'Сүрөттөмө 2200 белгиден ашпасын.',
      'Описание не должно превышать 2200 символов.',
      'Açıklama 2200 karakteri aşmamalı.',
    ],
    'preparing': [
      'Preparing video for Instagram...',
      'Видео Instagram үчүн даярдалууда...',
      'Подготовка видео для Instagram...',
      'Video Instagram için hazırlanıyor...',
    ],
    'processing': [
      'Instagram is preparing the video. Check again in one minute.',
      'Instagram видеону даярдоодо. Бир мүнөттөн кийин текшериңиз.',
      'Instagram подготавливает видео. Проверьте через минуту.',
      'Instagram videoyu hazırlıyor. Bir dakika sonra kontrol edin.',
    ],
    'creating': [
      'The preparation request was accepted. Check its status shortly.',
      'Даярдоо сурамы кабыл алынды. Бир аздан кийин текшериңиз.',
      'Запрос на подготовку принят. Проверьте статус немного позже.',
      'Hazırlama isteği kabul edildi. Biraz sonra kontrol edin.',
    ],
    'checking': [
      'Checking video status...',
      'Видеонун абалы текшерилүүдө...',
      'Проверка статуса видео...',
      'Video durumu kontrol ediliyor...',
    ],
    'wait': [
      'Wait one minute between status checks.',
      'Текшерүүлөрдүн ортосунда бир мүнөт күтүңүз.',
      'Подождите минуту между проверками.',
      'Kontroller arasında bir dakika bekleyin.',
    ],
    'ready': [
      'Video ready. Tap Publish to Instagram.',
      'Видео даяр. «Instagramга жарыялоо» баскычын басыңыз.',
      'Видео готово. Нажмите «Опубликовать в Instagram».',
      'Video hazır. “Instagram’da yayınla” düğmesine dokunun.',
    ],
    'failed': [
      'Instagram could not prepare the video or the container expired.',
      'Instagram видеону даярдай алган жок же даярдоо мөөнөтү бүттү.',
      'Instagram не подготовил видео или срок подготовки истёк.',
      'Instagram videoyu hazırlayamadı veya hazırlama süresi doldu.',
    ],
    'publishing': [
      'Publishing video to Instagram...',
      'Видео Instagramга жарыяланууда...',
      'Публикация видео в Instagram...',
      'Video Instagram’da yayınlanıyor...',
    ],
    'published': [
      'Video published to Instagram!',
      'Видео Instagramга жарыяланды!',
      'Видео опубликовано в Instagram!',
      'Video Instagram’da yayınlandı!',
    ],
    'reported': [
      'Instagram reports this video is published. Check your account.',
      'Instagram видеону жарыяланган деп көрсөтүүдө. Аккаунтуңуздан текшериңиз.',
      'Instagram сообщает, что видео опубликовано. Проверьте аккаунт.',
      'Instagram videonun yayınlandığını bildiriyor. Hesabınızı kontrol edin.',
    ],
    'publishUnknown': [
      'A publish request was sent. Check Instagram and the video status. Do not send it again.',
      'Жарыялоо сурамы жөнөтүлгөн. Instagramды жана видеонун абалын текшериңиз. Кайра жөнөтпөңүз.',
      'Запрос на публикацию отправлен. Проверьте Instagram и статус видео. Не отправляйте повторно.',
      'Yayınlama isteği gönderildi. Instagram’ı ve video durumunu kontrol edin. Tekrar göndermeyin.',
    ],
    'reconnect': [
      'Return to Jarvis and reconnect Instagram.',
      'Jarvisке кайтып, Instagramды кайра туташтырыңыз.',
      'Вернитесь в Jarvis и подключите Instagram заново.',
      'Jarvis’e dönüp Instagram’ı yeniden bağlayın.',
    ],
    'permission': [
      'Publishing permission is missing. Reconnect Instagram.',
      'Жарыялоого уруксат жок. Instagramды кайра туташтырыңыз.',
      'Нет разрешения на публикацию. Подключите Instagram заново.',
      'Yayınlama izni eksik. Instagram’ı yeniden bağlayın.',
    ],
    'notReady': [
      'Video is not ready. Check its status.',
      'Видео даяр эмес. Абалын текшериңиз.',
      'Видео не готово. Проверьте статус.',
      'Video hazır değil. Durumunu kontrol edin.',
    ],
    'error': [
      'The operation did not finish. Check your connection and the video status.',
      'Амал аягына чыккан жок. Байланышты жана видеонун абалын текшериңиз.',
      'Операция не завершена. Проверьте соединение и статус видео.',
      'İşlem tamamlanmadı. Bağlantınızı ve video durumunu kontrol edin.',
    ],
    'previewError': [
      'Could not open the video URL.',
      'Видеонун шилтемеси ачылган жок.',
      'Не удалось открыть ссылку на видео.',
      'Video bağlantısı açılamadı.',
    ],
  };

  final _api = ApiService();
  final _video = TextEditingController();
  final _caption = TextEditingController();

  bool _loaded = false;
  bool _busy = false;
  bool _storageFailed = false;
  bool _publishAttempted = false;

  String? _requestId;
  String? _jobId;

  String _state = '';
  String _containerStatus = '';
  String _notice = 'intro';

  DateTime? _lastCheck;

  String _t(String key) {
    final index = switch (widget.language) {
      'Кыргызча' => 1,
      'Русский' => 2,
      'Türkçe' => 3,
      _ => 0,
    };

    return (_texts[key] ?? _texts['error']!)[index];
  }

  bool _validId(dynamic value) {
    return value is String &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
  }

  bool _validVideo(String value) {
    final url = Uri.tryParse(value);

    return url != null &&
        url.scheme == 'https' &&
        url.host == 'easyai-server.onrender.com' &&
        !url.hasPort &&
        url.userInfo.isEmpty &&
        !url.hasQuery &&
        !url.hasFragment &&
        RegExp(r'^/videos/[a-zA-Z0-9_-]+\.mp4$')
            .hasMatch(url.path);
  }

  bool get _ready =>
      _jobId != null &&
      _state == 'processing' &&
      _containerStatus == 'FINISHED' &&
      !_publishAttempted;

  // Faqat tayyorlashdagi noaniq holatdan qayta boshlash mumkin.
  // Joylash natijasi noaniq bo'lsa, qayta yuborilmaydi.
  bool get _canRestart =>
      _jobId != null &&
      _state == 'needs_check' &&
      _containerStatus != 'PUBLISHED' &&
      !_publishAttempted;

  @override
  void initState() {
    super.initState();
    _video.text = widget.initialVideoUrl;
    _caption.text = widget.initialCaption;
    _restore();
  }

  Future<void> _restore() async {
    try {
      final saved = await _storage.read(key: _draftKey);
      if (!mounted) return;

      if (saved != null) {
        final data = jsonDecode(saved);

        if (data is! Map ||
            !_validId(data['requestId']) ||
            data['videoUrl'] is! String ||
            data['caption'] is! String ||
            (data['jobId'] != null &&
                !_validId(data['jobId']))) {
          throw const FormatException('INVALID_DRAFT');
        }

        _requestId = data['requestId'] as String;
        _jobId = data['jobId'] as String?;

        _video.text = data['videoUrl'] as String;
        _caption.text = data['caption'] as String;

        _state = data['state'] is String
            ? data['state'] as String
            : '';

        _publishAttempted =
            data['publishAttempted'] == true;

        // FINISHED holati har safar serverdan tekshiriladi.
        _notice = _state == 'published'
            ? 'published'
            : _publishAttempted
                ? 'publishUnknown'
                : _state == 'needs_check'
                    ? 'unknown'
                    : 'saved';
      }
    } catch (_) {
      _storageFailed = true;
      _notice = 'storage';
    } finally {
      if (mounted) {
        setState(() => _loaded = true);
      }
    }
  }

  Future<void> _save() async {
    if (_requestId == null) return;

    try {
      await _storage.write(
        key: _draftKey,
        value: jsonEncode({
          'requestId': _requestId,
          'jobId': _jobId,
          'videoUrl': _video.text.trim(),
          'caption': _caption.text,
          'state': _state,
          'publishAttempted': _publishAttempted,
        }),
      );
    } catch (_) {
      _storageFailed = true;
      rethrow;
    }
  }

  void _apply(Map<String, dynamic> data) {
    if (_validId(data['jobId'])) {
      _jobId = data['jobId'] as String;
    }

    if (data['state'] is String) {
      _state = data['state'] as String;
    }

    _containerStatus = data['containerStatus'] is String
        ? data['containerStatus'] as String
        : '';

    if (_state == 'published') {
      _notice = 'published';
    } else if (_containerStatus == 'PUBLISHED') {
      _notice = 'reported';
    } else if (_publishAttempted ||
        _state == 'publishing' ||
        _state == 'publish_needs_check') {
      _notice = 'publishUnknown';
    } else if (_containerStatus == 'ERROR' ||
        _containerStatus == 'EXPIRED') {
      _notice = 'failed';
    } else if (_state == 'needs_check') {
      _notice = 'unknown';
    } else if (_ready) {
      _notice = 'ready';
    } else if (_state == 'creating') {
      _notice = 'creating';
    } else {
      _notice = 'processing';
    }
  }

  String _errorKey(Object error) {
    if (_storageFailed) return 'storage';

    if (error is DioException) {
      final data = error.response?.data;
      final code = data is Map ? data['error'] : null;

      return switch (code) {
        'INSTAGRAM_RECONNECT_REQUIRED' ||
        'INSTAGRAM_SESSION_INVALID' =>
          'reconnect',
        'INSTAGRAM_PUBLISH_PERMISSION_REQUIRED' =>
          'permission',
        'USE_EASYAI_VIDEO_URL' ||
        'INVALID_VIDEO_URL' =>
          'invalidUrl',
        'INSTAGRAM_PREPARE_NEEDS_CHECK' =>
          'unknown',
        'INSTAGRAM_PUBLISH_NEEDS_CHECK' =>
          'publishUnknown',
        'REEL_NOT_READY' ||
        'REEL_NOT_READY_OR_ALREADY_SUBMITTED' =>
          'notReady',
        'VIDEO_TOO_LARGE' =>
          'large',
        'INVALID_MP4_VIDEO' ||
        'INVALID_VIDEO_UPLOAD' =>
          'mp4',
        'VIDEO_UPLOAD_BUSY' =>
          'uploadBusy',
        _ => 'error',
      };
    }

    return 'error';
  }

  Future<void> _chooseVideo() async {
    if (_busy ||
        !_loaded ||
        _storageFailed ||
        _requestId != null) {
      return;
    }

    final previous = _notice;

    setState(() {
      _busy = true;
      _notice = 'selecting';
    });

    try {
      final selected = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
      );

      if (!mounted) return;

      if (selected == null) {
        _notice = previous;
        return;
      }

      final size = await selected.length();
      if (!mounted) return;

      if (size > 100 * 1024 * 1024) {
        _notice = 'large';
        return;
      }

      if (size < 16) {
        _notice = 'mp4';
        return;
      }

      setState(() => _notice = 'uploading');

      final url = await _api.uploadInstagramVideo(
        selected.path,
      );

      if (!mounted) return;

      _video.text = url;
      _notice = 'uploaded';
    } catch (error) {
      if (!mounted) return;

      final key = _errorKey(error);
      _notice = key == 'error' ? 'uploadFailed' : key;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _prepare() async {
    if (_busy ||
        !_loaded ||
        _storageFailed ||
        _jobId != null) {
      return;
    }

    if (!_validVideo(_video.text.trim())) {
      setState(() => _notice = 'invalidUrl');
      return;
    }

    if (_caption.text.length > 2200) {
      setState(() => _notice = 'captionLong');
      return;
    }

    setState(() {
      _busy = true;
      _notice = 'preparing';
    });

    try {
      _requestId ??= _api.createInstagramReelRequestId();

      await _save();
      if (!mounted) return;

      final data = await _api.prepareInstagramReel(
        requestId: _requestId!,
        videoUrl: _video.text.trim(),
        caption: _caption.text,
      );

      if (!mounted) return;

      _apply(data);
      await _save();
    } catch (error) {
      if (!mounted) return;

      if (error is DioException) {
        final data = error.response?.data;

        if (data is Map && _validId(data['jobId'])) {
          _jobId = data['jobId'] as String;
          _state = 'needs_check';
          _containerStatus = '';

          try {
            await _save();
          } catch (_) {
            // _save saqlash xatosini belgilaydi.
          }
        }
      }

      if (mounted) {
        _notice = _errorKey(error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _check() async {
    if (_busy || _jobId == null || _storageFailed) {
      return;
    }

    final now = DateTime.now();

    if (_lastCheck != null &&
        now.difference(_lastCheck!) <
            const Duration(minutes: 1)) {
      setState(() => _notice = 'wait');
      return;
    }

    _lastCheck = now;

    setState(() {
      _busy = true;
      _notice = 'checking';
    });

    try {
      final data = await _api.getInstagramReelStatus(
        _jobId!,
      );

      if (!mounted) return;

      _apply(data);
      await _save();
    } catch (error) {
      if (mounted) {
        _notice = _errorKey(error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _preview() async {
    if (!_validVideo(_video.text.trim())) {
      setState(() => _notice = 'invalidUrl');
      return;
    }

    try {
      final opened = await launchUrl(
        Uri.parse(_video.text.trim()),
        mode: LaunchMode.externalApplication,
      );

      if (!opened && mounted) {
        setState(() => _notice = 'previewError');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _notice = 'previewError');
      }
    }
  }

  Future<void> _publish() async {
    if (_busy || !_ready || _storageFailed) return;

    setState(() => _busy = true);

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_t('confirmTitle')),
          content: SingleChildScrollView(
            child: Text(
              '${_t('confirmBody')}\n\n'
              '${_caption.text.isEmpty ? _t('noCaption') : _caption.text}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_t('publish')),
            ),
          ],
        ),
      );

      if (!mounted || confirmed != true) return;

      _publishAttempted = true;

      await _save();
      if (!mounted) return;

      setState(() => _notice = 'publishing');

      final data = await _api.publishInstagramReel(
        jobId: _jobId!,
        confirmed: true,
      );

      if (!mounted) return;

      _apply(data);
      await _save();
    } catch (error) {
      if (!mounted) return;

      // Bu aniq server xatosida joylash so'rovi yuborilmagan.
      if (error is DioException) {
        final data = error.response?.data;

        if (data is Map &&
            data['error'] == 'REEL_NOT_READY') {
          _publishAttempted = false;
          _containerStatus = '';

          try {
            await _save();
          } catch (_) {
            // Saqlash xatosi ko'rsatiladi.
          }
        }
      }

      if (mounted) {
        _notice = _errorKey(error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _newVideo() async {
    if (_busy ||
        _storageFailed ||
        (!_canRestart && _state != 'published')) {
      return;
    }

    final restarting = _canRestart;

    setState(() => _busy = true);

    try {
      if (restarting) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(_t('restartTitle')),
            content: Text(_t('restartBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(_t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(_t('restart')),
              ),
            ],
          ),
        );

        if (!mounted || confirmed != true) return;

        setState(() => _notice = 'checking');

        final data = await _api.getInstagramReelStatus(
          _jobId!,
        );

        if (!mounted) return;

        _apply(data);
        await _save();

        if (!mounted) return;

        // Server needs_check holatidagi eski ishni joylamaydi.
        // Jarayon davom etayotgan yoki joylash noaniq holatlarda
        // yangi so'rov boshlashga ruxsat berilmaydi.
        if (!_canRestart ||
            data['state'] != 'needs_check') {
          if (_notice != 'published' &&
              _notice != 'reported' &&
              _notice != 'publishUnknown') {
            _notice = 'resetBlocked';
          }

          return;
        }
      }

      await _storage.delete(key: _draftKey);
      if (!mounted) return;

      _requestId = null;
      _jobId = null;
      _state = '';
      _containerStatus = '';
      _publishAttempted = false;
      _lastCheck = null;

      if (!restarting) {
        _video.clear();
        _caption.clear();
      }

      _notice = restarting ? 'resetDone' : 'intro';
    } catch (error) {
      if (mounted) {
        _notice = _errorKey(error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _video.dispose();
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _loaded && !_busy && !_storageFailed;
    final locked = _requestId != null || !enabled;

    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Instagram Reels'),
          backgroundColor: Colors.black,
          actions: [
            IconButton(
              tooltip: AppTranslations.translate(
                widget.language,
                'aiReportButton',
              ),
              icon: const Icon(Icons.flag_outlined),
              onPressed: !_loaded || _busy
                  ? null
                  : () async {
                      await showAIContentReport(
                        context: context,
                        api: _api,
                        language: widget.language,
                        contentType: 'video',
                        content: _caption.text,
                        videoUrl: _video.text.trim(),
                      );
                    },
            ),
          ],
        ),
        body: !_loaded
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(_t('help')),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: enabled && !locked
                          ? _chooseVideo
                          : null,
                      icon: const Icon(
                        Icons.video_library_outlined,
                      ),
                      label: Text(_t('choose')),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _video,
                      readOnly: locked,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: _t('url'),
                        hintText:
                            'https://easyai-server.onrender.com/videos/...',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _caption,
                      readOnly: locked,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 2200,
                      decoration: InputDecoration(
                        labelText: _t('caption'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: enabled ? _preview : null,
                      icon: const Icon(
                        Icons.play_circle_outline,
                      ),
                      label: Text(_t('preview')),
                    ),
                    const SizedBox(height: 12),
                    if (_jobId == null)
                      FilledButton.icon(
                        onPressed: enabled ? _prepare : null,
                        icon: const Icon(
                          Icons.cloud_upload_outlined,
                        ),
                        label: Text(
                          _t(
                            _requestId == null
                                ? 'prepare'
                                : 'continue',
                          ),
                        ),
                      ),
                    if (_jobId != null &&
                        _state != 'published')
                      OutlinedButton.icon(
                        onPressed: enabled ? _check : null,
                        icon: const Icon(Icons.refresh),
                        label: Text(_t('check')),
                      ),
                    const SizedBox(height: 12),
                    if (_state != 'published')
                      FilledButton.icon(
                        onPressed:
                            enabled && _ready ? _publish : null,
                        icon: const Icon(Icons.publish),
                        label: Text(_t('publish')),
                      ),
                    if (_state == 'published')
                      FilledButton.icon(
                        onPressed: enabled ? _newVideo : null,
                        icon: const Icon(Icons.add),
                        label: Text(_t('new')),
                      ),
                    const SizedBox(height: 24),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: LinearProgressIndicator(),
                      ),
                    Text(
                      _t(_notice),
                      style: TextStyle(
                        fontSize: 16,
                        color: _state == 'published'
                            ? Colors.greenAccent
                            : Colors.white,
                      ),
                    ),
                    if (_canRestart) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: enabled ? _newVideo : null,
                        icon: const Icon(Icons.restart_alt),
                        label: Text(_t('restart')),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}