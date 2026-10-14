import 'package:flutter/material.dart';

import 'api_service.dart';
import 'credits_page.dart';

const _currencies = ['KGS', 'USD', 'UZS', 'RUB', 'TRY', 'EUR'];

const _productTexts = <String, List<String>>{
  'title': [
    'My products',
    'Менин товарларым',
    'Мои товары',
    'Ürünlerim',
  ],
  'credits': ['Credits', 'Кредиттер', 'Кредиты', 'Krediler'],
  'add': [
    'Add product',
    'Товар кошуу',
    'Добавить товар',
    'Ürün ekle',
  ],
  'edit': [
    'Edit product',
    'Товарды өзгөртүү',
    'Изменить товар',
    'Ürünü düzenle',
  ],
  'name': [
    'Product name',
    'Товардын аты',
    'Название товара',
    'Ürün adı',
  ],
  'description': [
    'Description, material and delivery',
    'Сүрөттөмө, материал жана жеткирүү',
    'Описание, материал и доставка',
    'Açıklama, malzeme ve teslimat',
  ],
  'descriptionHelp': [
    'Enter verified details: material, sizes, features and delivery terms.',
    'Так маалымат жазыңыз: материал, өлчөмдөр, өзгөчөлүктөр жана жеткирүү шарттары.',
    'Укажите точные сведения: материал, размеры, свойства и условия доставки.',
    'Doğru bilgileri yazın: malzeme, ölçüler, özellikler ve teslimat koşulları.',
  ],
  'price': ['Price', 'Баасы', 'Цена', 'Fiyat'],
  'priceHelp': [
    'For example: 1500 or 1500.50. Do not use thousands separators.',
    'Мисалы: 1500 же 1500.50. Миңдик бөлгүчтөрдү колдонбоңуз.',
    'Например: 1500 или 1500.50. Без разделителей тысяч.',
    'Örneğin: 1500 veya 1500.50. Binlik ayırıcı kullanmayın.',
  ],
  'currency': ['Currency', 'Валюта', 'Валюта', 'Para birimi'],
  'available': [
    'Available',
    'Сатыкта бар',
    'В наличии',
    'Stokta var',
  ],
  'unavailable': [
    'Unavailable',
    'Сатыкта жок',
    'Нет в наличии',
    'Stokta yok',
  ],
  'save': ['Save', 'Сактоо', 'Сохранить', 'Kaydet'],
  'cancel': ['Cancel', 'Жокко чыгаруу', 'Отмена', 'İptal'],
  'delete': ['Delete', 'Өчүрүү', 'Удалить', 'Sil'],
  'deleteTitle': [
    'Delete this product?',
    'Бул товарды өчүрөсүзбү?',
    'Удалить этот товар?',
    'Bu ürün silinsin mi?',
  ],
  'empty': [
    'No products yet. Add your first product.',
    'Азырынча товар жок. Биринчи товарды кошуңуз.',
    'Товаров пока нет. Добавьте первый товар.',
    'Henüz ürün yok. İlk ürününüzü ekleyin.',
  ],
  'refresh': ['Refresh', 'Жаңыртуу', 'Обновить', 'Yenile'],
  'loadError': [
    'Could not load products and settings. Check your connection and refresh.',
    'Товарлар жана жөндөөлөр жүктөлгөн жок. Байланышты текшерип, жаңыртыңыз.',
    'Не удалось загрузить товары и настройки. Проверьте соединение и обновите.',
    'Ürünler ve ayarlar yüklenemedi. Bağlantınızı kontrol edip yenileyin.',
  ],
  'saveError': [
    'Could not confirm saving. Keep this form open and try Save again.',
    'Сактоо ырасталган жок. Бул форманы жаппай, кайра сактаңыз.',
    'Не удалось подтвердить сохранение. Не закрывайте форму и повторите сохранение.',
    'Kayıt doğrulanamadı. Formu açık tutup tekrar Kaydet’e basın.',
  ],
  'deleteError': [
    'Could not confirm deletion. Refresh the list.',
    'Өчүрүү ырасталган жок. Тизмени жаңыртыңыз.',
    'Не удалось подтвердить удаление. Обновите список.',
    'Silme doğrulanamadı. Listeyi yenileyin.',
  ],
  'required': [
    'Enter this field.',
    'Бул талааны толтуруңуз.',
    'Заполните это поле.',
    'Bu alanı doldurun.',
  ],
  'invalidPrice': [
    'Enter a price from 0 to 99999999.99, with at most two decimal places.',
    '0дөн 99999999.99га чейинки бааны киргизиңиз. Үтүрдөн кийин эң көп эки сан.',
    'Введите цену от 0 до 99999999.99, не более двух знаков после запятой.',
    '0 ile 99999999.99 arasında, en fazla iki ondalık basamaklı fiyat girin.',
  ],
  'search': [
    'Search products',
    'Товар издөө',
    'Поиск товаров',
    'Ürün ara',
  ],
  'more': [
    'Load more',
    'Дагы жүктөө',
    'Загрузить ещё',
    'Daha fazla yükle',
  ],
  'replyHelp': [
    'Replies use your catalogue. AI assistance is limited; when unavailable, catalogue replies continue. The assistant cannot accept payments or confirm orders. You can also tell Jarvis to enable or disable Instagram Direct replies.',
    'Жооптор каталогуңузду колдонот. AI жардамында чектөө бар; жеткиликсиз болсо каталог жооптору уланат. Жардамчы төлөм кабыл албайт же буйрутманы ырастабайт. Jarvisке Instagram Direct жоопторун күйгүзүү же өчүрүү буйругун да бере аласыз.',
    'Ответы используют ваш каталог. Помощь ИИ ограничена; при её недоступности продолжаются ответы по каталогу. Помощник не принимает платежи и не подтверждает заказы. Ответы Direct можно включить или выключить командой Jarvis.',
    'Yanıtlar kataloğunuzu kullanır. AI yardımı sınırlıdır; kullanılamadığında katalog yanıtları sürer. Asistan ödeme alamaz veya sipariş onaylayamaz. Instagram Direct yanıtlarını Jarvis komutuyla da açıp kapatabilirsiniz.',
  ],
  'limit': [
    'You can save up to 1000 products.',
    'Эң көп 1000 товар сактай аласыз.',
    'Можно сохранить до 1000 товаров.',
    'En fazla 1000 ürün kaydedebilirsiniz.',
  ],
  'catalogHelp': [
    'Save accurate product names, prices and availability. Catalogue replies use these details.',
    'Товарлардын аттарын, бааларын жана бар-жогун так сактаңыз. Каталог жооптору ушул маалыматтарды колдонот.',
    'Сохраните точные названия, цены и наличие товаров. Ответы по каталогу используют эти сведения.',
    'Ürün adlarını, fiyatlarını ve stok durumunu doğru kaydedin. Katalog yanıtları bu bilgileri kullanır.',
  ],
  'account': [
    'Connected Instagram',
    'Туташкан Instagram',
    'Подключённый Instagram',
    'Bağlı Instagram',
  ],
  'autoReply': [
    'Automatic Direct replies',
    'Direct автоматтык жооптору',
    'Автоматические ответы в Direct',
    'Otomatik Direct yanıtları',
  ],
  'autoReplyOn': [
    'On — catalogue replies to new messages.',
    'Күйгүзүлгөн — жаңы билдирүүлөргө каталог боюнча жооп берет.',
    'Включены — ответы по каталогу на новые сообщения.',
    'Açık — yeni mesajlara katalog yanıtları.',
  ],
  'autoReplyOff': [
    'Off — incoming messages receive no automatic reply.',
    'Өчүрүлгөн — келген билдирүүлөргө автоматтык жооп берилбейт.',
    'Выключены — автоматические ответы не отправляются.',
    'Kapalı — gelen mesajlara otomatik yanıt gönderilmez.',
  ],
  'settingsUnknown': [
    'Checking settings… If checking fails, refresh to see the current state.',
    'Жөндөөлөр текшерилүүдө… Текшерүү бүтпөсө, учурдагы абалды көрүү үчүн жаңыртыңыз.',
    'Проверяем настройки… Если проверка не завершится, обновите текущий статус.',
    'Ayarlar kontrol ediliyor… Kontrol başarısız olursa güncel durumu görmek için yenileyin.',
  ],
  'connectRequired': [
    'Connect Instagram from Jarvis before enabling replies.',
    'Жоопторду күйгүзүүдөн мурун Jarvis аркылуу Instagram туташтырыңыз.',
    'Перед включением ответов подключите Instagram через Jarvis.',
    'Yanıtları açmadan önce Jarvis üzerinden Instagram bağlayın.',
  ],
  'permissionRequired': [
    'Reconnect Instagram and grant messaging permission.',
    'Instagramга кайра туташып, билдирүүлөргө уруксат бериңиз.',
    'Подключите Instagram заново и разрешите доступ к сообщениям.',
    'Instagram’ı yeniden bağlayıp mesajlaşma izni verin.',
  ],
  'enableTitle': [
    'Enable catalogue replies?',
    'Каталог жоопторун күйгүзөсүзбү?',
    'Включить ответы по каталогу?',
    'Katalog yanıtları açılsın mı?',
  ],
  'enableHelp': [
    'New messages can receive automatic replies with product prices and availability. For this initial version, customers should include the saved product name. Unknown products prompt a question. Orders are not confirmed.',
    'Жаңы билдирүүлөргө товар баасы жана бар-жогу тууралуу автоматтык жооп берилет. Бул алгачкы версияда кардар сакталган товар атын жазышы керек. Белгисиз товар боюнча тактоочу суроо берилет. Буйрутмалар ырасталбайт.',
    'На новые сообщения могут отправляться ответы с ценой и наличием. В этой первой версии клиенту нужно указать сохранённое название товара. Для неизвестного товара задаётся уточняющий вопрос. Заказы не подтверждаются.',
    'Yeni mesajlara ürün fiyatı ve stok bilgisiyle otomatik yanıt verilebilir. Bu ilk sürümde müşteri kayıtlı ürün adını yazmalıdır. Bilinmeyen ürün için açıklama istenir. Siparişler onaylanmaz.',
  ],
  'enable': ['Enable', 'Күйгүзүү', 'Включить', 'Etkinleştir'],
  'settingsError': [
    'Could not confirm the reply setting. Refresh before changing it again. If needed, reconnect Instagram with messaging permission.',
    'Жооп жөндөөсү ырасталган жок. Кайра өзгөртүүдөн мурун жаңыртыңыз. Керек болсо Instagramга билдирүү уруксаты менен кайра туташыңыз.',
    'Не удалось подтвердить настройку ответов. Обновите перед следующим изменением. При необходимости переподключите Instagram с доступом к сообщениям.',
    'Yanıt ayarı doğrulanamadı. Tekrar değiştirmeden önce yenileyin. Gerekirse Instagram’ı mesajlaşma izniyle yeniden bağlayın.',
  ],
};

String _pt(String language, String key) {
  final index = switch (language) {
    'Кыргызча' => 1,
    'Русский' => 2,
    'Türkçe' => 3,
    _ => 0,
  };

  return _productTexts[key]![index];
}

int? _parsePrice(String input) {
  final text = input.trim().replaceAll(',', '.');

  if (!RegExp(r'^\d{1,8}(?:\.\d{1,2})?$').hasMatch(text)) {
    return null;
  }

  final parts = text.split('.');
  final whole = int.parse(parts[0]);
  final fraction = parts.length == 2
      ? int.parse(parts[1].padRight(2, '0'))
      : 0;

  return whole * 100 + fraction;
}

String _formatPrice(int minor) {
  return '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
}

class _Product {
  final String id;
  final String name;
  final String description;
  final int priceMinor;
  final String currency;
  final bool available;

  const _Product({
    required this.id,
    required this.name,
    required this.description,
    required this.priceMinor,
    required this.currency,
    required this.available,
  });

  factory _Product.fromMap(Map<dynamic, dynamic> data) {
    final id = data['id'];
    final name = data['name'];
    final description = data['description'];
    final price = data['priceMinor'];
    final currency = data['currency'];
    final available = data['available'];

    if (id is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        name is! String ||
        description is! String ||
        price is! int ||
        price < 0 ||
        price > 9999999999 ||
        currency is! String ||
        !_currencies.contains(currency) ||
        available is! bool) {
      throw const FormatException('INVALID_PRODUCT_RESPONSE');
    }

    return _Product(
      id: id,
      name: name,
      description: description,
      priceMinor: price,
      currency: currency,
      available: available,
    );
  }
}

class InstagramProductsPage extends StatefulWidget {
  final String language;

  const InstagramProductsPage({
    super.key,
    required this.language,
  });

  @override
  State<InstagramProductsPage> createState() =>
      _InstagramProductsPageState();
}

class _InstagramProductsPageState
    extends State<InstagramProductsPage> {
  final _api = ApiService();
  final _search = TextEditingController();

  String? _nextCursor;
  bool _hasMore = false;
  int _total = 0;
  int _maxProducts = 1000;

  List<_Product> _products = [];
  String? _username;
  String? _error;

  bool _busy = false;
  bool _connected = false;
  bool _messagingPermission = false;
  bool _autoReplyEnabled = false;
  bool _settingsKnown = false;

  String _t(String key) => _pt(widget.language, key);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _settingsKnown = false;
    });

    try {
      final result = await _api.getInstagramProducts(
        search: _search.text.trim(),
        cursor: append ? _nextCursor : null,
        limit: 50,
      );

      final raw = result['products'];
      final connected = result['connected'];
      final messagingPermission = result['messagingPermission'];
      final autoReplyEnabled = result['autoReplyEnabled'];

      if (raw is! List ||
          raw.length > 50 ||
          connected is! bool ||
          messagingPermission is! bool ||
          autoReplyEnabled is! bool ||
          (autoReplyEnabled &&
              (!connected || !messagingPermission))) {
        throw const FormatException('INVALID_CATALOG_RESPONSE');
      }

      final products = raw.map((item) {
        if (item is! Map) {
          throw const FormatException('INVALID_PRODUCT_RESPONSE');
        }

        return _Product.fromMap(item);
      }).toList();

      if (!mounted) return;

      setState(() {
        _products = append
            ? [
                ..._products,
                ...products.where(
                  (item) => !_products.any(
                    (old) => old.id == item.id,
                  ),
                ),
              ]
            : products;

        _hasMore = result['hasMore'] == true;
        _nextCursor = result['nextCursor'] as String?;
        _total = result['total'] is int
            ? result['total'] as int
            : _products.length;
        _maxProducts = result['maxProducts'] is int
            ? result['maxProducts'] as int
            : 1000;

        _connected = connected;
        _messagingPermission = messagingPermission;
        _autoReplyEnabled = autoReplyEnabled;
        _settingsKnown = true;

        _username = connected && result['username'] is String
            ? result['username'] as String
            : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = _t('loadError'));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _setAutoReply(bool enabled) async {
    if (_busy || !_settingsKnown || _error != null) return;
    if (enabled && (!_connected || !_messagingPermission)) return;

    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_t('enableTitle')),
          content: SingleChildScrollView(
            child: Text(
              '${_username == null ? '' : '@$_username\n\n'}'
              '${_t('enableHelp')}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: Text(_t('cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: Text(_t('enable')),
            ),
          ],
        ),
      );

      if (!mounted || confirmed != true || _busy) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final saved = await _api.setInstagramAutoReplyEnabled(
        enabled,
      );

      if (!mounted) return;

      setState(() {
        _autoReplyEnabled = saved;
        _settingsKnown = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _settingsKnown = false;
          _error = _t('settingsError');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _edit([_Product? product]) async {
    if (_busy) return;

    final id = product?.id ??
        _api.createInstagramReelRequestId();

    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _ProductEditorPage(
          language: widget.language,
          productId: id,
          product: product,
        ),
      ),
    );

    if (!mounted) return;

    await _load();
  }

  Future<void> _delete(_Product product) async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_t('deleteTitle')),
        content: Text(product.name),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            child: Text(_t('delete')),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _api.deleteInstagramProduct(product.id);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _t('deleteError'));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }

    if (!mounted) return;

    if (_error == null) {
      await _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _replySubtitle {
    if (!_settingsKnown) return _t('settingsUnknown');
    if (!_connected) return _t('connectRequired');
    if (!_messagingPermission) return _t('permissionRequired');

    return _t(
      _autoReplyEnabled ? 'autoReplyOn' : 'autoReplyOff',
    );
  }

  @override
  Widget build(BuildContext context) {
    final canChangeReplies = !_busy &&
        _error == null &&
        _settingsKnown &&
        (_autoReplyEnabled ||
            (_connected && _messagingPermission));

    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(_t('title')),
          backgroundColor: Colors.black,
          actions: [
            IconButton(
              tooltip: _t('credits'),
              onPressed: _busy
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CreditsPage(
                            language: widget.language,
                          ),
                        ),
                      ),
              icon: const Icon(
                Icons.account_balance_wallet_outlined,
              ),
            ),
            IconButton(
              tooltip: _t('refresh'),
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(_t('catalogHelp')),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              maxLength: 120,
              enabled: !_busy,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                labelText: _t('search'),
                suffixIcon: IconButton(
                  onPressed: _busy ? null : () => _load(),
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_username != null) ...[
              Text(
                '${_t('account')}: @$_username',
                style: const TextStyle(
                  color: Colors.greenAccent,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Card(
              margin: EdgeInsets.zero,
              child: SwitchListTile(
                title: Text(_t('autoReply')),
                subtitle: Text(_replySubtitle),
                value: _autoReplyEnabled,
                isThreeLine: true,
                onChanged: canChangeReplies
                    ? _setAutoReply
                    : null,
              ),
            ),
            Text(_t('replyHelp')),
            const SizedBox(height: 16),
            Text(
              '${_products.length} / $_total · $_maxProducts',
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  _busy || _error != null || _total >= _maxProducts
                      ? null
                      : () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(_t('add')),
            ),
            if (_total >= _maxProducts) ...[
              const SizedBox(height: 8),
              Text(_t('limit')),
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.orangeAccent,
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _load,
                child: Text(_t('refresh')),
              ),
            ],
            const SizedBox(height: 16),
            if (_hasMore)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _load(append: true),
                child: Text(_t('more')),
              ),
            if (!_busy &&
                _error == null &&
                _products.isEmpty)
              Text(_t('empty')),
            for (final product in _products)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 19,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(product.description),
                      const SizedBox(height: 12),
                      Text(
                        '${_formatPrice(product.priceMinor)} '
                        '${product.currency}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t(
                          product.available
                              ? 'available'
                              : 'unavailable',
                        ),
                        style: TextStyle(
                          color: product.available
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _edit(product),
                            icon: const Icon(
                              Icons.edit_outlined,
                            ),
                            label: Text(_t('edit')),
                          ),
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _delete(product),
                            icon: const Icon(
                              Icons.delete_outline,
                            ),
                            label: Text(_t('delete')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductEditorPage extends StatefulWidget {
  final String language;
  final String productId;
  final _Product? product;

  const _ProductEditorPage({
    required this.language,
    required this.productId,
    this.product,
  });

  @override
  State<_ProductEditorPage> createState() =>
      _ProductEditorPageState();
}

class _ProductEditorPageState
    extends State<_ProductEditorPage> {
  final _api = ApiService();
  final _form = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();

  String _currency = 'KGS';
  bool _available = true;
  bool _busy = false;
  String? _error;

  String _t(String key) => _pt(widget.language, key);

  @override
  void initState() {
    super.initState();

    final product = widget.product;

    if (product != null) {
      _name.text = product.name;
      _description.text = product.description;
      _price.text = _formatPrice(product.priceMinor);
      _currency = product.currency;
      _available = product.available;
    }
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;

    final price = _parsePrice(_price.text);
    if (price == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _api.saveInstagramProduct(
        productId: widget.productId,
        name: _name.text.trim(),
        description: _description.text.trim(),
        priceMinor: price,
        currency: _currency,
        available: _available,
      );

      if (!mounted) return;

      setState(() => _busy = false);
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _t('saveError');
        });
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: PopScope(
        canPop: !_busy,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(
              _t(widget.product == null ? 'add' : 'edit'),
            ),
            backgroundColor: Colors.black,
            automaticallyImplyLeading: !_busy,
          ),
          body: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: _t('name'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty
                          ? _t('required')
                          : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  enabled: !_busy,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    labelText: _t('description'),
                    helperText: _t('descriptionHelp'),
                    helperMaxLines: 4,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty
                          ? _t('required')
                          : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _price,
                  enabled: !_busy,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _t('price'),
                    helperText: _t('priceHelp'),
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      _parsePrice(value ?? '') == null
                          ? _t('invalidPrice')
                          : null,
                ),
                const SizedBox(height: 20),
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: _t('currency'),
                    border: const OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _currency,
                      isExpanded: true,
                      items: [
                        for (final currency in _currencies)
                          DropdownMenuItem(
                            value: currency,
                            child: Text(currency),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(
                                  () => _currency = value,
                                );
                              }
                            },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t('available')),
                  value: _available,
                  onChanged: _busy
                      ? null
                      : (value) =>
                          setState(() => _available = value),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_t('save')),
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}