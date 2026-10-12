import crypto from "node:crypto";
import { FieldValue } from "firebase-admin/firestore";
import {
  createInstagramSalesPlanner,
} from "./instagram_sales_ai.js";

const DAY_MS = 24 * 60 * 60 * 1000;
const PREPARING_MS = 120000;

const CURRENCIES = [
  "KGS", "USD", "UZS", "RUB", "TRY", "EUR",
];

const TEXTS = {
  en: {
    intro: "Automatic shop assistant.",
    greeting: "Hello! Which product can I help you with?",
    price: "Price",
    available: "Available",
    unavailable: "Currently unavailable",
    question: "Which product are you asking about? Please specify its name.",
    empty: "The product catalogue is currently empty.",
    human: "I do not have verified information about this. Please check with the seller.",
    order: "An order has not been confirmed. Please arrange the purchase with the seller.",
  },
  ky: {
    intro: "Дүкөндүн автоматтык жардамчысы.",
    greeting: "Саламатсызбы! Кайсы товар боюнча жардам керек?",
    price: "Баасы",
    available: "Сатыкта бар",
    unavailable: "Азыр сатыкта жок",
    question: "Кайсы товар жөнүндө сурап жатасыз? Атын тактаңыз.",
    empty: "Товарлар каталогу азыр бош.",
    human: "Бул тууралуу так маалыматым жок. Сатуучудан тактаңыз.",
    order: "Буйрутма ырасталган жок. Сатып алууну сатуучу менен макулдашыңыз.",
  },
  ru: {
    intro: "Автоматический помощник магазина.",
    greeting: "Здравствуйте! С каким товаром помочь?",
    price: "Цена",
    available: "В наличии",
    unavailable: "Сейчас нет в наличии",
    question: "О каком товаре вы спрашиваете? Уточните название.",
    empty: "Каталог товаров сейчас пуст.",
    human: "У меня нет проверенной информации об этом. Уточните у продавца.",
    order: "Заказ не подтверждён. Согласуйте покупку с продавцом.",
  },
  tr: {
    intro: "Otomatik mağaza asistanı.",
    greeting: "Merhaba! Hangi ürün hakkında yardımcı olabilirim?",
    price: "Fiyat",
    available: "Stokta var",
    unavailable: "Şu anda stokta yok",
    question: "Hangi ürünü soruyorsunuz? Lütfen adını belirtin.",
    empty: "Ürün kataloğu şu anda boş.",
    human: "Bu konuda doğrulanmış bilgim yok. Lütfen satıcıya danışın.",
    order: "Sipariş onaylanmadı. Satın alma işlemini satıcıyla görüşün.",
  },
  uz: {
    intro: "Do‘konning avtomatik yordamchisi.",
    greeting: "Salom! Qaysi mahsulot bo‘yicha yordam beray?",
    price: "Narxi",
    available: "Sotuvda bor",
    unavailable: "Hozir sotuvda yo‘q",
    question: "Qaysi mahsulot haqida so‘rayapsiz? Nomini aniqlashtiring.",
    empty: "Mahsulot katalogi hozir bo‘sh.",
    human: "Bu haqda aniq ma’lumotim yo‘q. Sotuvchidan aniqlashtiring.",
    order: "Buyurtma tasdiqlanmadi. Xaridni sotuvchi bilan kelishing.",
  },
};

function languageOf(text) {
  const value = text.toLowerCase();

  if (
    /[ңөү]/i.test(value) ||
    /салам|канча|баасы|барбы|товарлар/i.test(value)
  ) return "ky";

  if (
    /[ıİğşç]/i.test(text) ||
    /\b(merhaba|fiyat|stok|sipariş)\b/i.test(value)
  ) return "tr";

  if (/[а-яё]/i.test(value)) return "ru";

  if (
    /\b(salom|qancha|narx|narxi|mahsulot|bormi|buyurtma)\b/i
      .test(value)
  ) return "uz";

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
    product &&
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

function priceOf(product) {
  const whole = Math.floor(product.priceMinor / 100);
  const fraction = String(
    product.priceMinor % 100,
  ).padStart(2, "0");

  return `${whole}.${fraction} ${product.currency}`;
}

function productNames(products) {
  return products
    .slice(0, 5)
    .map((product) => `• ${product.name}`)
    .join("\n");
}

function productReply(product, labels, intent) {
  const lines = [
    labels.intro,
    product.name,
  ];

  if (intent !== "availability") {
    lines.push(`${labels.price}: ${priceOf(product)}`);
  }

  lines.push(
    product.available
      ? labels.available
      : labels.unavailable,
  );

  if (intent === "details" || intent === "order") {
    lines.push(product.description.slice(0, 450));
  }

  if (intent === "order") {
    lines.push(labels.order);
  }

  return lines.filter(Boolean).join("\n\n");
}

export function buildCatalogReply(text, products) {
  const labels = TEXTS[languageOf(text)];
  const catalogue = products.filter(validProduct);

  if (!catalogue.length) {
    return `${labels.intro}\n\n${labels.empty}`;
  }

  const question = ` ${normalize(text)} `;

  const matches = catalogue.filter((product) => {
    const name = normalize(product.name);
    return name && question.includes(` ${name} `);
  });

  if (matches.length !== 1) {
    return [
      labels.intro,
      labels.question,
      productNames(catalogue),
    ].join("\n\n");
  }

  return productReply(matches[0], labels, "details");
}

export function buildPlannedReply(decision, products) {
  const labels = TEXTS[decision.language] || TEXTS.en;
  const catalogue = products.filter(validProduct);

  if (decision.intent === "greeting") {
    return `${labels.intro}\n\n${labels.greeting}`;
  }

  if (decision.intent === "human") {
    return `${labels.intro}\n\n${labels.human}`;
  }

  if (!catalogue.length) {
    return `${labels.intro}\n\n${labels.empty}`;
  }

  if (decision.intent === "catalogue") {
    return [
      labels.intro,
      productNames(catalogue),
      labels.question,
    ].join("\n\n");
  }

  const product = catalogue.find(
    (item) => item.id === decision.productId,
  );

  if (
    !product ||
    !["price", "availability", "details", "order"]
      .includes(decision.intent)
  ) {
    return [
      labels.intro,
      labels.question,
      productNames(catalogue),
    ].join("\n\n");
  }

  return productReply(product, labels, decision.intent);
}

function blockedReason(account, business, message) {
  const now = Date.now();

  if (
    !account ||
    account.profileVerified !== true ||
    typeof account.expiresAt?.toMillis !== "function" ||
    account.expiresAt.toMillis() <= now ||
    account.instagramUserId !== message.instagramUserId
  ) return "INSTAGRAM_RECONNECT_REQUIRED";

  if (
    !Array.isArray(account.permissions) ||
    !account.permissions.includes(
      "instagram_business_manage_messages",
    )
  ) return "INSTAGRAM_MESSAGING_PERMISSION_REQUIRED";

  if (
    business?.autoReplyEnabled !== true ||
    business?.autoReplyInstagramUserId !==
      message.instagramUserId ||
    typeof business?.autoReplyEnabledAt?.toMillis !==
      "function"
  ) return "AUTO_REPLY_DISABLED";

  if (
    !Number.isSafeInteger(message.timestamp) ||
    message.timestamp < business.autoReplyEnabledAt.toMillis() ||
    message.timestamp > now + 60000 ||
    now - message.timestamp >= DAY_MS
  ) return "MESSAGE_OUTSIDE_REPLY_WINDOW";

  return null;
}

export function startInstagramMessageWorker(db, { sendReply }) {
  const inbox = db.collection("instagramPrivateMessageInbox");
  const connections = db.collection("instagramPrivateConnections");
  const businesses = db.collection("instagramPrivateBusinesses");
  const conversations = db.collection("instagramPrivateConversations");

  const planSalesReply = createInstagramSalesPlanner();
  const pending = new Map();
  const retryTimers = new Map();

  let busy = false;
  let stopped = false;
  let unsubscribe = null;
  let restartTimer = null;

  function threadId(ownerId, message) {
    return crypto
      .createHash("sha256")
      .update(JSON.stringify([
        ownerId,
        message.instagramUserId,
        message.senderId,
      ]))
      .digest("hex");
  }

  function schedule(id, delay) {
    if (stopped || retryTimers.has(id)) return;

    retryTimers.set(id, setTimeout(() => {
      retryTimers.delete(id);
      if (stopped) return;

      pending.set(id, 0);
      void drain();
    }, Math.max(1000, delay)));
  }

  async function prepareReply(id) {
    const ref = inbox.doc(id);
    const claimId = crypto.randomBytes(16).toString("hex");

    const taken = await db.runTransaction(async (tx) => {
      const saved = await tx.get(ref);
      const message = saved.data();

      if (!message) return null;

      if (message.state === "reply_ready") {
        return { ready: true };
      }

      if (
        !["received", "reply_preparing"].includes(message.state)
      ) return null;

      const now = Date.now();

      if (
        message.state === "reply_preparing" &&
        Number.isSafeInteger(message.replyLeaseUntil) &&
        message.replyLeaseUntil > now
      ) {
        return {
          wait: message.replyLeaseUntil - now + 1000,
        };
      }

      const skip = (reason) => {
        tx.update(ref, {
          state: "reply_skipped",
          replyError: reason,
          replyUpdatedAt: FieldValue.serverTimestamp(),
        });

        return null;
      };

      if (
        typeof message.instagramUserId !== "string" ||
        !/^\d+$/.test(message.instagramUserId) ||
        typeof message.senderId !== "string" ||
        !/^\d+$/.test(message.senderId) ||
        message.senderId === message.instagramUserId ||
        typeof message.text !== "string" ||
        !message.text.trim() ||
        message.text.length > 20000
      ) return skip("INVALID_INCOMING_MESSAGE");

      const matching = await tx.get(
        connections
          .where("instagramUserId", "==", message.instagramUserId)
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

      const reason = blockedReason(account, business, message);
      if (reason) return skip(reason);

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

      const attempts = message.replyPrepareAttempts || 0;

      if (attempts >= 3) {
        return skip("REPLY_PREPARATION_LIMIT");
      }

      if (minuteCount >= 10 || dayCount >= 200) {
        return skip("AUTO_REPLY_RATE_LIMIT");
      }

      const productsSnapshot = await tx.get(
        businessRef.collection("products").limit(50),
      );

      const products = productsSnapshot.docs
        .map((doc) => ({
          ...doc.data(),
          id: doc.id,
        }))
        .filter(validProduct);

      const conversationId = threadId(ownerId, message);

      const savedConversation = await tx.get(
        conversations.doc(conversationId),
      );

      const conversation = savedConversation.data();
      const enabledAt = business.autoReplyEnabledAt.toMillis();

      const history =
        conversation?.enabledAt === enabledAt &&
        Array.isArray(conversation?.history)
          ? conversation.history.slice(-4)
          : [];

      const aiCount =
        business.salesAiUsageDay === day
          ? business.salesAiUsageDayCount || 0
          : 0;

      // Sinov uchun: bir akkauntga kuniga 50 AI so‘rovi.
      // Qolgan xabarlarda oddiy katalog javobi ishlaydi.
      const useAi =
        !!process.env.JARVIS_API_KEY?.trim() &&
        message.text.length <= 2000 &&
        products.length > 0 &&
        aiCount < 50;

      tx.set(businessRef, {
        replyUsageMinute: minute,
        replyUsageMinuteCount: minuteCount + 1,
        replyUsageDay: day,
        replyUsageDayCount: dayCount + 1,
        ...(useAi
          ? {
              salesAiUsageDay: day,
              salesAiUsageDayCount: aiCount + 1,
            }
          : {}),
      }, { merge: true });

      tx.update(ref, {
        state: "reply_preparing",
        replyClaimId: claimId,
        replyLeaseUntil: now + PREPARING_MS,
        replyPrepareAttempts: attempts + 1,
        replyUpdatedAt: FieldValue.serverTimestamp(),
      });

      return {
        ownerId,
        message,
        products,
        history,
        useAi,
        conversationId,
        enabledAt,
      };
    });

    if (!taken) return false;
    if (taken.ready) return true;

    if (taken.wait) {
      schedule(id, taken.wait);
      return false;
    }

    let decision = null;
    let aiError = null;

    // AI chaqiruvi transaction tashqarisida bajariladi.
    if (taken.useAi) {
      try {
        decision = await planSalesReply({
          text: taken.message.text,
          products: taken.products,
          history: taken.history,
        });
      } catch {
        aiError = "INSTAGRAM_SALES_AI_FAILED";
      }
    }

    return db.runTransaction(async (tx) => {
      const current = await tx.get(ref);
      const message = current.data();

      if (
        !message ||
        message.state !== "reply_preparing" ||
        message.replyClaimId !== claimId
      ) return false;

      const savedAccount = await tx.get(
        connections.doc(taken.ownerId),
      );

      const businessRef = businesses.doc(taken.ownerId);
      const savedBusiness = await tx.get(businessRef);
      const business = savedBusiness.data();

      const reason = blockedReason(
        savedAccount.data(),
        business,
        message,
      );

      if (
        reason ||
        business.autoReplyEnabledAt.toMillis() !== taken.enabledAt
      ) {
        tx.update(ref, {
          state: "reply_skipped",
          replyError: reason || "AUTO_REPLY_SETTINGS_CHANGED",
          replyUpdatedAt: FieldValue.serverTimestamp(),
        });

        return false;
      }

      // Javob oldidan katalogning hozirgi qiymatlarini o‘qiymiz.
      const freshSnapshot = await tx.get(
        businessRef.collection("products").limit(50),
      );

      const products = freshSnapshot.docs
        .map((doc) => ({
          ...doc.data(),
          id: doc.id,
        }))
        .filter(validProduct);

      const replyText = decision
        ? buildPlannedReply(decision, products)
        : buildCatalogReply(message.text, products);

      if (!replyText || replyText.length > 1000) {
        tx.update(ref, {
          state: "reply_failed",
          replyError: "INVALID_CATALOG_REPLY",
        });

        return false;
      }

      tx.update(ref, {
        state: "reply_ready",
        replyOwnerId: taken.ownerId,
        replyText,
        replyMode: decision
          ? "ai_catalogue"
          : "catalogue_fallback",
        replyDecision: decision,
        replyAiError: aiError,
        replyConversationId: taken.conversationId,
        replyContextEnabledAt: taken.enabledAt,
        replyNeedsHuman:
          decision?.intent === "human" ||
          decision?.intent === "order",
        replyPreparedAt: FieldValue.serverTimestamp(),
      });

      return true;
    });
  }

  async function rememberReply(id) {
    const ref = inbox.doc(id);

    await db.runTransaction(async (tx) => {
      const saved = await tx.get(ref);
      const message = saved.data();

      if (
        message?.state !== "replied" ||
        typeof message.replyConversationId !== "string" ||
        !/^[a-f0-9]{64}$/.test(message.replyConversationId) ||
        typeof message.replyText !== "string"
      ) return;

      const conversationRef = conversations.doc(
        message.replyConversationId,
      );

      const savedConversation = await tx.get(conversationRef);
      const previous = savedConversation.data();

      if (
        previous?.enabledAt === message.replyContextEnabledAt &&
        (
          previous.lastInboxId === id ||
          previous.lastMessageTimestamp > message.timestamp
        )
      ) return;

      const history =
        previous?.enabledAt === message.replyContextEnabledAt &&
        Array.isArray(previous?.history)
          ? previous.history.slice(-3)
          : [];

      history.push({
        userText: message.text.slice(0, 1000),
        replyText: message.replyText.slice(0, 1000),
      });

      tx.set(conversationRef, {
        ownerId: message.replyOwnerId,
        instagramUserId: message.instagramUserId,
        senderId: message.senderId,
        enabledAt: message.replyContextEnabledAt,
        lastInboxId: id,
        lastMessageTimestamp: message.timestamp,
        history,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
  }

  async function drain() {
    if (busy || stopped) return;
    busy = true;

    try {
      while (!stopped && pending.size) {
        const [id] = [...pending.entries()]
          .sort((a, b) => a[1] - b[1])[0];

        pending.delete(id);

        try {
          const ready = await prepareReply(id);

          if (ready && !stopped) {
            const sent = await sendReply(id);

            if (sent?.messageId) {
              await rememberReply(id);
            }
          }
        } catch (error) {
          console.error(
            "Instagram message worker: processing failed",
            error?.code || error?.name || "UNKNOWN",
          );

          schedule(id, 10000);
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
      .where("state", "in", [
        "received",
        "reply_preparing",
        "reply_ready",
      ])
      .limit(50)
      .onSnapshot(
        (snapshot) => {
          for (const change of snapshot.docChanges()) {
            const id = change.doc.id;

            if (change.type === "removed") {
              pending.delete(id);

              const timer = retryTimers.get(id);
              if (timer) clearTimeout(timer);
              retryTimers.delete(id);
            } else {
              const timestamp = change.doc.data().timestamp;

              pending.set(
                id,
                Number.isSafeInteger(timestamp) ? timestamp : 0,
              );
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

    for (const timer of retryTimers.values()) {
      clearTimeout(timer);
    }

    retryTimers.clear();
  };
}