import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'api_service.dart';
import 'purchase_service.dart';

class CreditsPage extends StatefulWidget {
  const CreditsPage({
    super.key,
    required this.language,
  });

  final String language;

  @override
  State<CreditsPage> createState() => _CreditsPageState();
}

class _CreditsPageState extends State<CreditsPage>
    with WidgetsBindingObserver {
  final _api = ApiService();
  final _purchase = CreditPurchaseService.instance;

  Map<String, dynamic>? _account;
  ProductDetails? _product;

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

    _purchase.start();
    _purchase.state.addListener(_onPurchase);

    unawaited(_refresh());

    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) {
        if (mounted &&
            _purchase.state.value ==
                CreditPurchaseState.verificationPending) {
          unawaited(_refresh());
        }
      },
    );
  }

  void _onPurchase() {
    if (!mounted) return;

    setState(() {});

    if (_purchase.state.value == CreditPurchaseState.completed) {
      unawaited(_refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (!mounted || _loading) return;

    setState(() {
      _loading = true;
      _failed = false;
    });

    try {
      final account = await _api.getCreditAccount(widget.language);

      if (!mounted) return;

      setState(() => _account = account);

      ProductDetails? product;

      try {
        product = await _purchase.product();
      } catch (_) {}

      if (!mounted) return;

      setState(() => _product = product);
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

  String get _purchaseText {
    return switch (_purchase.state.value) {
      CreditPurchaseState.idle => '',
      CreditPurchaseState.opening => _t(
          'Opening Google Play…',
          'Google Play ачылууда…',
          'Открываем Google Play…',
          'Google Play açılıyor…',
        ),
      CreditPurchaseState.pending => _t(
          'Payment is pending. Credits are added after Google Play confirms payment.',
          'Төлөм күтүлүүдө. Google Play ырастагандан кийин кредит кошулат.',
          'Платёж ожидается. Кредиты добавляются после подтверждения Google Play.',
          'Ödeme bekleniyor. Google Play doğruladıktan sonra krediler eklenir.',
        ),
      CreditPurchaseState.verifying => _t(
          'Verifying your purchase…',
          'Сатып алуу текшерилүүдө…',
          'Проверяем покупку…',
          'Satın alma doğrulanıyor…',
        ),
      CreditPurchaseState.completed => _t(
          'Purchase verified. Your balance has been updated.',
          'Сатып алуу ырасталды. Баланс жаңыртылды.',
          'Покупка подтверждена. Баланс обновлён.',
          'Satın alma doğrulandı. Bakiyeniz güncellendi.',
        ),
      CreditPurchaseState.cancelled => _t(
          'Purchase cancelled.',
          'Сатып алуу жокко чыгарылды.',
          'Покупка отменена.',
          'Satın alma iptal edildi.',
        ),
      CreditPurchaseState.failed => _t(
          'Could not open or complete the purchase. Try again.',
          'Сатып алуу ачылган же аяктаган жок. Кайра аракет кылыңыз.',
          'Не удалось открыть или завершить покупку. Попробуйте снова.',
          'Satın alma açılamadı veya tamamlanamadı. Yeniden deneyin.',
        ),
      CreditPurchaseState.verificationPending => _t(
          'Purchase verification is pending. Check the purchase below before buying again.',
          'Сатып алууну ырастоо күтүлүүдө. Кайра сатып алуудан мурун төмөндөн текшериңиз.',
          'Подтверждение покупки ожидается. Проверьте её кнопкой ниже перед повторной покупкой.',
          'Satın alma doğrulaması bekleniyor. Yeniden satın almadan önce aşağıdan kontrol edin.',
        ),
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _purchase.state.removeListener(_onPurchase);
    _timer?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = _account?['productCredits'] ?? 100;

    final blocked = _loading ||
        _product == null ||
        _account == null ||
        [
          CreditPurchaseState.opening,
          CreditPurchaseState.pending,
          CreditPurchaseState.verifying,
          CreditPurchaseState.verificationPending,
        ].contains(_purchase.state.value);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          _t(
            'Credits',
            'Кредиттер',
            'Кредиты',
            'Krediler',
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_loading) const LinearProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            _t(
              'Your balance',
              'Сиздин баланс',
              'Ваш баланс',
              'Bakiyeniz',
            ),
            style: const TextStyle(fontSize: 20),
          ),
          Text(
            _account == null ? '—' : '${_account!['credits']}',
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (_account != null)
            Text(
              _t(
                'Free videos: ${_account!['freeVideosRemaining']}\n'
                    'Free chat replies: ${_account!['freeChatRemaining']}\n'
                    'Free live minutes: ${_account!['freeLiveMinutesRemaining']}',
                'Акысыз видео: ${_account!['freeVideosRemaining']}\n'
                    'Акысыз жооп: ${_account!['freeChatRemaining']}\n'
                    'Акысыз жандуу мүнөт: ${_account!['freeLiveMinutesRemaining']}',
                'Бесплатные видео: ${_account!['freeVideosRemaining']}\n'
                    'Бесплатные ответы: ${_account!['freeChatRemaining']}\n'
                    'Бесплатные минуты: ${_account!['freeLiveMinutesRemaining']}',
                'Ücretsiz video: ${_account!['freeVideosRemaining']}\n'
                    'Ücretsiz yanıt: ${_account!['freeChatRemaining']}\n'
                    'Ücretsiz canlı dakika: ${_account!['freeLiveMinutesRemaining']}',
              ),
            ),
          const SizedBox(height: 24),
          Text(
            _t(
              'One video: 6 credits. Chat reply: 1 credit. '
                  'Live conversation: 1 credit per started minute after the free trial.',
              'Бир видео: 6 кредит. Жооп: 1 кредит. '
                  'Акысыз сыноодон кийин жандуу сүйлөшүүнүн башталган ар бир мүнөтү: 1 кредит.',
              'Видео: 6 кредитов. Ответ: 1 кредит. '
                  'После бесплатного периода каждая начатая минута разговора: 1 кредит.',
              'Video: 6 kredi. Yanıt: 1 kredi. '
                  'Ücretsiz denemeden sonra canlı sohbetin başlayan her dakikası: 1 kredi.',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: blocked
                ? null
                : () async {
                    await _purchase.buy();
                  },
            child: Text(
              _t(
                    'Buy $count credits',
                    '$count кредит сатып алуу',
                    'Купить $count кредитов',
                    '$count kredi satın al',
                  ) +
                  (_product == null ? '' : ' · ${_product!.price}'),
            ),
          ),
          if (!_loading && _product == null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _t(
                  'Google Play purchases are unavailable on this installation. '
                      'Test purchases using the Play test version.',
                  'Бул орнотууда Google Play сатып алуусу жеткиликсиз. '
                      'Play сыноо версиясын колдонуңуз.',
                  'В этой установке покупки Google Play недоступны. '
                      'Используйте тестовую версию из Play.',
                  'Bu kurulumda Google Play satın almaları kullanılamıyor. '
                      'Play test sürümünü kullanın.',
                ),
              ),
            ),
          if (_failed)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _t(
                  'Could not refresh your balance. Try again.',
                  'Баланс жаңыртылган жок. Кайра аракет кылыңыз.',
                  'Не удалось обновить баланс. Попробуйте снова.',
                  'Bakiye yenilenemedi. Yeniden deneyin.',
                ),
              ),
            ),
          if (_purchaseText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text(_purchaseText),
            ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () async {
              await _purchase.checkPending();
              await _refresh();
            },
            child: Text(
              _t(
                'Check an unfinished purchase',
                'Аяктабаган сатып алууну текшерүү',
                'Проверить незавершённую покупку',
                'Tamamlanmamış satın almayı kontrol et',
              ),
            ),
          ),
        ],
      ),
    );
  }
}