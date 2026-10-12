import { FieldValue } from "firebase-admin/firestore";

const DAY_MS = 24 * 60 * 60 * 1000;
const CURRENCIES = ["KGS", "USD", "UZS", "RUB", "TRY", "EUR"];

const TEXTS = {
  en: {
    intro: "Automatic catalogue reply.",
    price: "Price",
    available: "Available",
    unavailable: "Currently unavailable",
    question: "Which product are you asking about? Please send its name.",
    empty: "The product catalogue is currently empty.",
    order: "This message does not confirm an order.",
  },
  ky: {
    intro: "Каталог боюнча автоматтык жооп.",
    price: "Баасы",
    available: "Сатыкта бар",
    unavailable: "Азыр сатыкта жок",
    question: "Кайсы товар жөнүндө сурап жатасыз? Атын жазыңыз.",
    empty: "Товарлар каталогу азыр бош.",
    order: "Бул билдирүү буйрутманы ырастабайт.",
  },
  ru: {
    intro: "Автоматический ответ по каталогу.",
    price: "Цена",
    available: "В наличии",
    unavailable: "Сейчас нет в наличии",
    question: "О каком товаре вы спрашиваете? Напишите его название.",
    empty: "Каталог товаров сейчас пуст.",
    order: "Это сообщение не подтверждает заказ.",
  },
  tr: {
    intro: "Otomatik katalog yanıtı.",
    price: "Fiyat",
    available: "Stokta var",
    unavailable: "Şu anda stokta yok",
    question: "Hangi ürünü soruyorsunuz? Lütfen adını yazın.",
    empty: "Ürün kataloğu şu anda boş.",
    order: "Bu mesaj sipariş onayı değildir.",
  },
  uz: {
    intro: "Avtomatik katalog javobi.",
    price: "Narxi",
    available: "Sotuvda bor",
    unavailable: "Hozir sotuvda yo‘q",
    question: "Qaysi mahsulot haqida so‘rayapsiz? Nomini yozing.",
    empty: "Mahsulot katalogi hozir bo‘sh.",
    order: "Bu xabar buyurtmani tasdiqlamaydi.",
  },
};

function languageOf(text) {
  const value = text.toLowerCase();

  if (
    /[ңөү]/i.test(value) ||
    /салам|канча|баасы|барбы|товарлар/i.test(value)
  ) {
    return "ky";
  }

  if (
    /[ıİğşç]/i.test(text) ||
    /\b(merhaba|fiyat|stok|sipariş)\b/i.test(value)
  ) {
    return "tr";
  }

  if (/[а-яё]/i.test(value)) {
    return "ru";
  }

  if (
    /\b(salom|qancha|narx|narxi|mahsulot|bormi|buyurtma)\b/i
      .test(value)
  ) {
    return "uz";
  }

  return "en";
}

function normalize(text) {
  return text
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function validProduct(product) {
  return (
    typeof product.name === "string" &&
    !!product.name.trim() &&
    product.name.length <= 120 &&
    typeof product.description === "string" &&
    product.description.length <= 2000 &&
    Number.isSafeInteger(product.priceMinor) &&
    product.priceMinor >= 0 &&
    product.priceMinor <= 9999999999 &&
    CURRENCIES.includes(product.currency) &&
    typeof product.available === "boolean"
  );
}

export function buildCatalogReply(text, products) {
  const labels = TEXTS[languageOf(text)];
  const catalogue = products.filter(validProduct);

  if (catalogue.length === 0) {
    return `${labels.intro}\n${labels.empty}`;
  }

  const question = ` ${normalize(text)} `;

  const matches = catalogue.filter((product) => {
    const name = normalize(product.name);
    return name && question.includes(` ${name} `);
  });

  // Bir nechta mahsulot mos tushsa taxmin qilmaymiz.
  if (matches.length !== 1) {
    const names = catalogue
      .slice(0, 5)
      .map((product) => `• ${product.name}`)
      .join("\n");

    return [
      labels.intro,
      labels.question,
      names,
    ].join("\n\n");
  }

  const product = matches[0];

  const price =
    `${Math.floor(product.priceMinor / 100)}.` +
    String(product.priceMinor % 100).padStart(2, "0");

  return [
    labels.intro,
    product.name,
    `${labels.price}: ${price} ${product.currency}`,
    product.available
      ? labels.available
      : labels.unavailable,
    product.description.slice(0, 450),
    labels.order,
  ].join("\n\n");
}

export function startInstagramMessageWorker(db, { sendReply }) {
  const inbox = db.collection("instagramPrivateMessageInbox");
  const connections = db.collection("instagramPrivateConnections");
  const businesses = db.collection("instagramPrivateBusinesses");

  const pending = new Set();

  let busy = false;
  let stopped = false;
  let unsubscribe = null;
  let restartTimer = null;

  async function prepareReply(id) {
    const ref = inbox.doc(id);

    return db.runTransaction(async (tx) => {
      const saved = await tx.get(ref);
      const message = saved.data();

      if (!message) return false;

      if (message.state === "reply_ready") {
        return true;
      }

      if (message.state !== "received") {
        return false;
      }

      const skip = (reason) => {
        tx.update(ref, {
          state: "reply_skipped",
          replyError: reason,
          replyUpdatedAt: FieldValue.serverTimestamp(),
        });

        return false;
      };

      if (
        typeof message.instagramUserId !== "string" ||
        !/^\d+$/.test(message.instagramUserId) ||
        typeof message.senderId !== "string" ||
        !/^\d+$/.test(message.senderId) ||
        message.senderId === message.instagramUserId ||
        typeof message.text !== "string" ||
        !message.text.trim() ||
        message.text.length > 20000 ||
        !Number.isSafeInteger(message.timestamp)
      ) {
        return skip("INVALID_INCOMING_MESSAGE");
      }

      const matching = await tx.get(
        connections
          .where(
            "instagramUserId",
            "==",
            message.instagramUserId,
          )
          .limit(2),
      );

      if (matching.size !== 1) {
        return skip("INSTAGRAM_ACCOUNT_OWNER_UNRESOLVED");
      }

      const ownerId = matching.docs[0].id;
      const account = matching.docs[0].data();
      const businessRef = businesses.doc(ownerId);

      const savedBusiness = await tx.get(businessRef);
      const business = savedBusiness.data();

      const now = Date.now();

      if (
        account.profileVerified !== true ||
        typeof account.expiresAt?.toMillis !== "function" ||
        account.expiresAt.toMillis() <= now
      ) {
        return skip("INSTAGRAM_RECONNECT_REQUIRED");
      }

      if (
        !Array.isArray(account.permissions) ||
        !account.permissions.includes(
          "instagram_business_manage_messages",
        )
      ) {
        return skip("INSTAGRAM_MESSAGING_PERMISSION_REQUIRED");
      }

      if (
        business?.autoReplyEnabled !== true ||
        business?.autoReplyInstagramUserId !==
          message.instagramUserId ||
        typeof business?.autoReplyEnabledAt?.toMillis !==
          "function"
      ) {
        return skip("AUTO_REPLY_DISABLED");
      }

      if (
        message.timestamp <
          business.autoReplyEnabledAt.toMillis() ||
        message.timestamp > now + 60 * 1000 ||
        now - message.timestamp >= DAY_MS
      ) {
        return skip("MESSAGE_OUTSIDE_REPLY_WINDOW");
      }

      const minute = Math.floor(now / 60000);
      const day = Math.floor(now / DAY_MS);

      const minuteCount =
        business.replyUsageMinute === minute
          ? business.replyUsageMinuteCount || 0
          : 0;

      const dayCount =
        business.replyUsageDay === day
          ? business.replyUsageDayCount || 0
          : 0;

      // Dastlabki sinov uchun yuborish chegaralari.
      if (minuteCount >= 10 || dayCount >= 200) {
        return skip("AUTO_REPLY_RATE_LIMIT");
      }

      const products = await tx.get(
        businessRef.collection("products").limit(50),
      );

      const replyText = buildCatalogReply(
        message.text,
        products.docs.map((doc) => doc.data()),
      );

      if (!replyText || replyText.length > 1000) {
        return skip("INVALID_CATALOG_REPLY");
      }

      tx.set(
        businessRef,
        {
          replyUsageMinute: minute,
          replyUsageMinuteCount: minuteCount + 1,
          replyUsageDay: day,
          replyUsageDayCount: dayCount + 1,
        },
        { merge: true },
      );

      tx.update(ref, {
        state: "reply_ready",
        replyOwnerId: ownerId,
        replyText,
        replyPreparedAt: FieldValue.serverTimestamp(),
      });

      return true;
    });
  }

  async function drain() {
    if (busy || stopped) return;

    busy = true;

    try {
      while (!stopped && pending.size > 0) {
        const id = pending.values().next().value;
        pending.delete(id);

        try {
          const ready = await prepareReply(id);

          if (ready && !stopped) {
            await sendReply(id);
          }
        } catch (error) {
          console.error(
            "Instagram message worker: processing failed",
            error?.code || error?.name || "UNKNOWN",
          );

          // Tashqi yuborishni emas, navbat holatini
          // keyingi ulanishda yana tekshiramiz.
          reconnect();
          break;
        }
      }
    } finally {
      busy = false;
    }
  }

  function reconnect() {
    if (stopped || restartTimer) return;

    if (unsubscribe) {
      unsubscribe();
      unsubscribe = null;
    }

    restartTimer = setTimeout(() => {
      restartTimer = null;
      listen();
    }, 10000);
  }

  function listen() {
    if (stopped) return;

    unsubscribe = inbox
      .where("state", "in", ["received", "reply_ready"])
      .limit(50)
      .onSnapshot(
        (snapshot) => {
          for (const change of snapshot.docChanges()) {
            if (change.type === "removed") {
              pending.delete(change.doc.id);
            } else {
              pending.add(change.doc.id);
            }
          }

          void drain();
        },
        (error) => {
          console.error(
            "Instagram message worker: listener failed",
            error?.code || "UNKNOWN",
          );

          reconnect();
        },
      );
  }

  listen();

  return () => {
    stopped = true;
    pending.clear();

    if (unsubscribe) unsubscribe();
    if (restartTimer) clearTimeout(restartTimer);
  };
}