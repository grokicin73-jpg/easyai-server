import express from "express";
import {
  FieldValue,
  FieldPath,
} from "firebase-admin/firestore";

const CURRENCIES = [
  "KGS", "USD", "UZS", "RUB", "TRY", "EUR",
];

const MAX_PRODUCTS = 1000;
const DEFAULT_PAGE_SIZE = 50;
const MAX_PAGE_SIZE = 50;

function validId(value) {
  return (
    typeof value === "string" &&
    /^[a-f0-9]{64}$/.test(value)
  );
}

function normalizeSearch(value) {
  return value
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[‘’ʻʼ`´]/g, "'")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function validateProduct(body) {
  if (
    !body ||
    typeof body !== "object" ||
    Array.isArray(body)
  ) {
    return null;
  }

  const {
    name,
    description,
    priceMinor,
    currency,
    available,
  } = body;

  if (
    typeof name !== "string" ||
    !name.trim() ||
    name.trim().length > 120 ||
    typeof description !== "string" ||
    !description.trim() ||
    description.trim().length > 2000 ||
    !Number.isSafeInteger(priceMinor) ||
    priceMinor < 0 ||
    priceMinor > 9999999999 ||
    !CURRENCIES.includes(currency) ||
    typeof available !== "boolean"
  ) {
    return null;
  }

  return {
    name: name.trim(),
    description: description.trim(),
    priceMinor,
    currency,
    available,
  };
}

function publicProduct(doc) {
  const product = doc.data();

  return {
    id: doc.id,
    name: product.name,
    description: product.description,
    priceMinor: product.priceMinor,
    currency: product.currency,
    available: product.available,
  };
}

function isConnected(account) {
  return (
    !!account &&
    account.profileVerified === true &&
    typeof account.instagramUserId === "string" &&
    /^\d+$/.test(account.instagramUserId) &&
    typeof account.expiresAt?.toMillis === "function" &&
    account.expiresAt.toMillis() > Date.now()
  );
}

function canMessage(account) {
  return (
    isConnected(account) &&
    Array.isArray(account.permissions) &&
    account.permissions.includes(
      "instagram_business_manage_messages",
    )
  );
}

function parseListOptions(query) {
  const limitText =
    query.limit === undefined
      ? String(DEFAULT_PAGE_SIZE)
      : query.limit;

  const cursor =
    query.cursor === undefined
      ? ""
      : query.cursor;

  const search =
    query.q === undefined
      ? ""
      : query.q;

  if (
    typeof limitText !== "string" ||
    !/^\d{1,2}$/.test(limitText) ||
    typeof cursor !== "string" ||
    (cursor !== "" && !validId(cursor)) ||
    typeof search !== "string" ||
    search.length > 120
  ) {
    return null;
  }

  const limit = Number(limitText);

  if (limit < 1 || limit > MAX_PAGE_SIZE) {
    return null;
  }

  return {
    limit,
    cursor,
    search: normalizeSearch(search),
  };
}

export function attachInstagramBusiness(app, db, { owner }) {
  const router = express.Router();

  const businesses = db.collection(
    "instagramPrivateBusinesses",
  );

  const connections = db.collection(
    "instagramPrivateConnections",
  );

  const wrap = (fn) => (req, res, next) =>
    Promise.resolve()
      .then(() => fn(req, res, next))
      .catch(next);

  router.use(
    wrap(async (req, res, next) => {
      res.set("Cache-Control", "no-store");

      const ownerId = await owner(req, res);
      if (!ownerId) return;

      req.instagramOwnerId = ownerId;
      next();
    }),
  );

  // Katalog sahifalari va nom/tavsif bo‘yicha qidiruv.
  // Har bir so‘rov faqat shu egasining katalogini o‘qiydi.
  router.get(
    "/products",
    wrap(async (req, res) => {
      const options = parseListOptions(req.query);

      if (!options) {
        return res.status(400).json({
          success: false,
          error: "INVALID_CATALOG_QUERY",
        });
      }

      const businessRef = businesses.doc(
        req.instagramOwnerId,
      );

      const productsRef = businessRef.collection("products");

      let products;
      let hasMore;
      let nextCursor;
      let total;
      let matchedTotal = null;

      if (options.search) {
        // 1000 tagacha katalogda qidiruv serverda bajariladi.
        // Telefon va AI ga butun katalog yuborilmaydi.
        const snapshot = await productsRef
          .orderBy(FieldPath.documentId())
          .limit(MAX_PRODUCTS + 1)
          .get();

        if (snapshot.size > MAX_PRODUCTS) {
          throw new Error("CATALOG_LIMIT_EXCEEDED");
        }

        total = snapshot.size;

        const terms = options.search.split(" ");

        const matches = snapshot.docs.filter((doc) => {
          const product = doc.data();

          const searchable = normalizeSearch(
            [
              typeof product.name === "string"
                ? product.name
                : "",
              typeof product.description === "string"
                ? product.description
                : "",
            ].join(" "),
          );

          return terms.every(
            (term) => searchable.includes(term),
          );
        });

        matchedTotal = matches.length;

        const remaining = options.cursor
          ? matches.filter(
              (doc) => doc.id > options.cursor,
            )
          : matches;

        const page = remaining.slice(0, options.limit);

        products = page.map(publicProduct);
        hasMore = remaining.length > page.length;
        nextCursor =
          hasMore && page.length
            ? page[page.length - 1].id
            : null;
      } else {
        let pageQuery = productsRef.orderBy(
          FieldPath.documentId(),
        );

        if (options.cursor) {
          pageQuery = pageQuery.startAfter(options.cursor);
        }

        const [snapshot, countSnapshot] = await Promise.all([
          pageQuery.limit(options.limit + 1).get(),
          productsRef.count().get(),
        ]);

        total = countSnapshot.data().count;

        const page = snapshot.docs.slice(0, options.limit);

        products = page.map(publicProduct);
        hasMore = snapshot.size > options.limit;
        nextCursor =
          hasMore && page.length
            ? page[page.length - 1].id
            : null;
      }

      const [savedAccount, savedBusiness] = await Promise.all([
        connections.doc(req.instagramOwnerId).get(),
        businessRef.get(),
      ]);

      const account = savedAccount.data();
      const business = savedBusiness.data();

      const connected = isConnected(account);
      const messagingPermission = canMessage(account);

      const autoReplyEnabled =
        messagingPermission &&
        business?.autoReplyEnabled === true &&
        business?.autoReplyInstagramUserId ===
          account?.instagramUserId;

      return res.json({
        success: true,
        products,
        total,
        matchedTotal,
        maxProducts: MAX_PRODUCTS,
        pageSize: options.limit,
        hasMore,
        nextCursor,
        search: options.search,
        username: account?.username || null,
        connected,
        messagingPermission,
        autoReplyEnabled,
      });
    }),
  );

  // Avtomatik javob sozlamasini faqat egasi boshqaradi.
  router.put(
    "/settings",
    wrap(async (req, res) => {
      const body = req.body;

      if (
        !body ||
        typeof body !== "object" ||
        Array.isArray(body) ||
        typeof body.autoReplyEnabled !== "boolean"
      ) {
        return res.status(400).json({
          success: false,
          error: "INVALID_BUSINESS_SETTINGS",
        });
      }

      const enabled = body.autoReplyEnabled;

      const businessRef = businesses.doc(
        req.instagramOwnerId,
      );

      const connectionRef = connections.doc(
        req.instagramOwnerId,
      );

      const result = await db.runTransaction(async (tx) => {
        const saved = await tx.get(connectionRef);
        const savedBusiness = await tx.get(businessRef);

        const account = saved.data();
        const previous = savedBusiness.data();

        if (enabled && !isConnected(account)) {
          return {
            status: 409,
            error: "INSTAGRAM_RECONNECT_REQUIRED",
          };
        }

        if (enabled && !canMessage(account)) {
          return {
            status: 403,
            error: "INSTAGRAM_MESSAGING_PERMISSION_REQUIRED",
          };
        }

        const alreadyEnabled =
          enabled &&
          previous?.autoReplyEnabled === true &&
          previous?.autoReplyInstagramUserId ===
            account?.instagramUserId &&
          typeof previous?.autoReplyEnabledAt?.toMillis ===
            "function";

        tx.set(
          businessRef,
          {
            autoReplyEnabled: enabled,
            autoReplyInstagramUserId: enabled
              ? account.instagramUserId
              : null,
            autoReplyEnabledAt: enabled
              ? alreadyEnabled
                ? previous.autoReplyEnabledAt
                : FieldValue.serverTimestamp()
              : null,
            settingsUpdatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        return {
          autoReplyEnabled: enabled,
        };
      });

      if (result.error) {
        return res.status(result.status).json({
          success: false,
          error: result.error,
        });
      }

      return res.json({
        success: true,
        autoReplyEnabled: result.autoReplyEnabled,
      });
    }),
  );

  // Mahsulot yaratish yoki tahrirlash.
  router.put(
    "/products/:productId",
    wrap(async (req, res) => {
      if (!validId(req.params.productId)) {
        return res.status(400).json({
          success: false,
          error: "INVALID_PRODUCT_ID",
        });
      }

      const product = validateProduct(req.body);

      if (!product) {
        return res.status(400).json({
          success: false,
          error: "INVALID_PRODUCT",
        });
      }

      const businessRef = businesses.doc(
        req.instagramOwnerId,
      );

      const productsRef = businessRef.collection("products");

      const productRef = productsRef.doc(
        req.params.productId,
      );

      const accepted = await db.runTransaction(async (tx) => {
        const savedBusiness = await tx.get(businessRef);
        const existing = await tx.get(productRef);

        const savedCount = savedBusiness.data()?.productCount;

        let count;

        if (
          Number.isSafeInteger(savedCount) &&
          savedCount >= 0
        ) {
          count = savedCount;
        } else {
          // Hisoblagich yo‘q bo‘lsa mavjud katalogdan tiklanadi.
          const snapshot = await tx.get(
            productsRef.limit(MAX_PRODUCTS + 1),
          );

          count = snapshot.size;
        }

        if (!existing.exists && count >= MAX_PRODUCTS) {
          return false;
        }

        tx.set(
          productRef,
          {
            ...product,
            updatedAt: FieldValue.serverTimestamp(),
            ...(!existing.exists
              ? {
                  createdAt: FieldValue.serverTimestamp(),
                }
              : {}),
          },
          { merge: true },
        );

        tx.set(
          businessRef,
          {
            productCount: count + (existing.exists ? 0 : 1),
            catalogRevision: FieldValue.increment(1),
            catalogUpdatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        return true;
      });

      if (!accepted) {
        return res.status(409).json({
          success: false,
          error: "CATALOG_FULL",
          maxProducts: MAX_PRODUCTS,
        });
      }

      return res.json({
        success: true,
        product: {
          id: req.params.productId,
          ...product,
        },
      });
    }),
  );

  // Mahsulotni faqat katalog egasi o‘chiradi.
  router.delete(
    "/products/:productId",
    wrap(async (req, res) => {
      if (!validId(req.params.productId)) {
        return res.status(400).json({
          success: false,
          error: "INVALID_PRODUCT_ID",
        });
      }

      const businessRef = businesses.doc(
        req.instagramOwnerId,
      );

      const productsRef = businessRef.collection("products");

      const productRef = productsRef.doc(
        req.params.productId,
      );

      await db.runTransaction(async (tx) => {
        const savedBusiness = await tx.get(businessRef);
        const product = await tx.get(productRef);

        if (!product.exists) return;

        const savedCount = savedBusiness.data()?.productCount;

        let count;

        if (
          Number.isSafeInteger(savedCount) &&
          savedCount >= 1
        ) {
          count = savedCount;
        } else {
          const snapshot = await tx.get(
            productsRef.limit(MAX_PRODUCTS + 1),
          );

          count = snapshot.size;
        }

        tx.delete(productRef);

        tx.set(
          businessRef,
          {
            productCount: Math.max(0, count - 1),
            catalogRevision: FieldValue.increment(1),
            catalogUpdatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      });

      return res.json({
        success: true,
      });
    }),
  );

  router.use((error, req, res, next) => {
    if (res.headersSent) {
      return next(error);
    }

    console.error(
      "INSTAGRAM CATALOG ERROR:",
      error?.code || "CATALOG_REQUEST_FAILED",
    );

    return res.status(503).json({
      success: false,
      error: "CATALOG_REQUEST_FAILED",
    });
  });

  app.use("/api/instagram/business", router);
}