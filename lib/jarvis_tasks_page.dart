import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'ai_content_report.dart';
import 'credits_page.dart';
import 'translations.dart';

class JarvisTasksPage extends StatefulWidget {
  const JarvisTasksPage({
    super.key,
    required this.language,
  });

  final String language;

  @override
  State<JarvisTasksPage> createState() => _JarvisTasksPageState();
}

class _JarvisTasksPageState extends State<JarvisTasksPage>
    with WidgetsBindingObserver {
  final _api = ApiService();

  List<Map<String, dynamic>> _tasks = [];

  bool _loading = false;
  bool _failed = false;

  Timer? _timer;

  String _t(String en, String ky, String ru, String tr) {
    return switch (widget.language) {
      'Кыргызча' => ky,
      'Русский' => ru,
      'Türkçe' => tr,
      _ => en,
    };
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    unawaited(_refresh());

    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_refresh()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (!mounted || _loading) return;

    setState(() => _loading = true);

    try {
      final tasks = await _api.getAutomationTasks(widget.language);

      if (mounted) {
        setState(() {
          _tasks = tasks;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _state(String state) {
    return switch (state) {
      'queued' => _t(
          'Queued',
          'Кезекте',
          'В очереди',
          'Sırada',
        ),
      'starting' || 'generating' => _t(
          'Creating video…',
          'Видео жаралууда…',
          'Создаём видео…',
          'Video oluşturuluyor…',
        ),
      'generated' || 'preparing' || 'processing' => _t(
          'Preparing Instagram publication…',
          'Instagramга жарыялоо даярдалууда…',
          'Готовим публикацию в Instagram…',
          'Instagram yayını hazırlanıyor…',
        ),
      'publishing' => _t(
          'Publishing…',
          'Жарыяланууда…',
          'Публикуем…',
          'Yayınlanıyor…',
        ),
      'ready' => _t(
          'Video created',
          'Видео жаралды',
          'Видео создано',
          'Video oluşturuldu',
        ),
      'published' => _t(
          'Published to Instagram',
          'Instagramга жарыяланды',
          'Опубликовано в Instagram',
          'Instagram’da yayınlandı',
        ),
      'failed' => _t(
          'Task could not finish',
          'Тапшырма аяктаган жок',
          'Задача не завершена',
          'Görev tamamlanamadı',
        ),
      _ => _t(
          'Result needs checking. Do not repeat the command.',
          'Натыйжаны текшерүү керек. Буйрукту кайталабаңыз.',
          'Результат требует проверки. Не повторяйте команду.',
          'Sonuç kontrol edilmeli. Komutu tekrar etmeyin.',
        ),
    };
  }

  String _error(String code) {
    if (code == 'FREE_LIMIT_REACHED') {
      return _t(
        'Not enough credits to create this video.',
        'Видео жаратууга кредит жетишсиз.',
        'Недостаточно кредитов для видео.',
        'Video için yeterli kredi yok.',
      );
    }

    if (code.contains('ACCOUNT_CHANGED')) {
      return _t(
        'The connected Instagram account changed. '
            'No publication was sent to the new account.',
        'Туташкан Instagram аккаунту өзгөрдү. '
            'Жаңы аккаунтка жарыялоо жөнөтүлгөн жок.',
        'Подключённый аккаунт изменился. '
            'Публикация в новый аккаунт не отправлена.',
        'Bağlı Instagram hesabı değişti. '
            'Yeni hesaba yayın gönderilmedi.',
      );
    }

    if (code.contains('RECONNECT') ||
        code.contains('PERMISSION')) {
      return _t(
        'Reconnect Instagram and check its permissions.',
        'Instagramды кайра туташтырып, уруксаттарын текшериңиз.',
        'Подключите Instagram заново и проверьте разрешения.',
        'Instagram’ı yeniden bağlayıp izinleri kontrol edin.',
      );
    }

    if (code.contains('UNKNOWN') ||
        code.contains('TIMED_OUT')) {
      return _t(
        'The result is uncertain. Check the task and Instagram; '
            'contact support if it remains unresolved.',
        'Натыйжа белгисиз. Тапшырманы жана Instagramды текшериңиз; '
            'чечилбесе колдоого кайрылыңыз.',
        'Результат неизвестен. Проверьте задачу и Instagram; '
            'если статус не меняется, обратитесь в поддержку.',
        'Sonuç bilinmiyor. Görevi ve Instagram’ı kontrol edin; '
            'çözülmezse destekle iletişime geçin.',
      );
    }

    return _t(
      'The task encountered a problem. '
          'Your generated video, if available, is shown below.',
      'Тапшырмада маселе чыкты. '
          'Жаратылган видео бар болсо төмөндө көрсөтүлөт.',
      'В задаче возникла проблема. '
          'Созданное видео, если доступно, показано ниже.',
      'Görevde bir sorun oluştu. '
          'Oluşturulan video mevcutsa aşağıda gösterilir.',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          _t(
            'Tasks',
            'Тапшырмалар',
            'Задачи',
            'Görevler',
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CreditsPage(
                    language: widget.language,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_loading) const LinearProgressIndicator(),
          Text(
            _t(
              'An explicit create-and-publish command starts one video '
                  'for the connected Instagram account. Tasks continue '
                  'on the server after you leave this page.',
              'Түзүү жана жарыялоо тууралуу так буйрук туташкан Instagram '
                  'аккаунту үчүн бир видеону баштайт. Баракты жапканда '
                  'тапшырма серверде уланат.',
              'Явная команда создать и опубликовать запускает один ролик '
                  'для подключённого Instagram. Задача продолжается '
                  'на сервере после закрытия страницы.',
              'Açık bir oluştur ve yayınla komutu, bağlı Instagram hesabı '
                  'için bir video başlatır. Sayfayı kapatsanız da görev '
                  'sunucuda devam eder.',
            ),
          ),
          const SizedBox(height: 20),
          if (_failed)
            Text(
              _t(
                'Could not refresh tasks. Try again.',
                'Тапшырмалар жаңыртылган жок. Кайра аракет кылыңыз.',
                'Не удалось обновить задачи. Попробуйте снова.',
                'Görevler yenilenemedi. Yeniden deneyin.',
              ),
            ),
          if (!_loading && !_failed && _tasks.isEmpty)
            Text(
              _t(
                'No video tasks yet. Tell Jarvis what to create.',
                'Азырынча тапшырма жок. Jarvisке эмне жаратуу керектигин айтыңыз.',
                'Задач пока нет. Скажите Jarvis, что создать.',
                'Henüz görev yok. Jarvis’e ne oluşturacağını söyleyin.',
              ),
            ),
          for (final task in _tasks)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task['title'] as String? ?? '',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _state(task['state'] as String? ?? ''),
                    ),
                    if (task['username'] is String)
                      Text('@${task['username']}'),
                    if (task['error'] is String)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error(task['error'] as String),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SelectableText(
                      task['caption'] as String? ?? '',
                    ),
                    if (task['videoUrl'] is String)
                      TextButton.icon(
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text(
                          _t(
                            'Watch video',
                            'Видеону көрүү',
                            'Посмотреть видео',
                            'Videoyu izle',
                          ),
                        ),
                        onPressed: () async {
                          final uri = Uri.tryParse(
                            task['videoUrl'] as String,
                          );

                          if (uri != null &&
                              uri.scheme == 'https' &&
                              uri.host == 'easyai-server.onrender.com') {
                            try {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            } catch (_) {}
                          }
                        },
                      ),
                    if ((task['state'] as String? ?? '')
                        .endsWith('needs_check'))
                      TextButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          _t(
                            'Check result',
                            'Натыйжаны текшерүү',
                            'Проверить результат',
                            'Sonucu kontrol et',
                          ),
                        ),
                        onPressed: _loading
                            ? null
                            : () async {
                                try {
                                  await _api.checkAutomationTask(
                                    widget.language,
                                    task['id'] as String,
                                  );
                                } catch (_) {}

                                await _refresh();
                              },
                      ),
                    TextButton.icon(
                      icon: const Icon(Icons.flag_outlined),
                      label: Text(
                        AppTranslations.translate(
                          widget.language,
                          'aiReportButton',
                        ),
                      ),
                      onPressed: () {
                         showAIContentReport(
                          context: context,
                          api: _api,
                          language: widget.language,
                          contentType:
                              task['videoUrl'] == null ? 'chat' : 'video',
                          content:
                              '${task['title']}\n${task['caption']}',
                          prompt: task['prompt'] as String? ?? '',
                          model: 'Jarvis / Veo 3',
                          videoUrl: task['videoUrl'] as String? ?? '',
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}