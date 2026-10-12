import express from "express";
import { FieldValue } from "firebase-admin/firestore";

const CURRENCIES = ["KGS", "USD", "UZS", "RUB", "TRY", "EUR"];
const MAX_PRODUCTS = 50;

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

export function attachInstagramBusiness(app, db, { owner }) {
  const router = express.Router();

  const businesses = db.collection(
    "instagramPrivateBusinesses",
  );

  const connections = db.collection(
    "instagramPrivateConnections",
  );

  const validId = (value) =>
    typeof value === "string" &&
    /^[a-f0-9]{64}$/.test(value);

  const wrap = (fn) => (req, res, next) =>
    Promise.resolve(fn(req, res, next)).catch(next);

  router.use(
    wrap(async (req, res, next) => {
      res.set("Cache-Control", "no-store");

      const ownerId = await owner(req, res);
      if (!ownerId) return;

      req.instagramOwnerId = ownerId;
      next();
    }),
  );

  // Faqat shu foydalanuvchining mahsulotlarini olish.
  router.get(
    "/products",
    wrap(async (req, res) => {
      const snapshot = await businesses
        .doc(req.instagramOwnerId)
        .collection("products")
        .limit(MAX_PRODUCTS)
        .get();

      const products = snapshot.docs
        .map((doc) => {
          const product = doc.data();

          return {
            id: doc.id,
            name: product.name,
            description: product.description,
            priceMinor: product.priceMinor,
            currency: product.currency,
            available: product.available,
          };
        })
        .sort((a, b) => a.name.localeCompare(b.name));

      const saved = await connections
        .doc(req.instagramOwnerId)
        .get();

      const account = saved.data();

      const connected =
        !!account &&
        account.profileVerified === true &&
        account.expiresAt?.toMillis() > Date.now();

      const messagingPermission =
        connected &&
        Array.isArray(account.permissions) &&
        account.permissions.includes(
          "instagram_business_manage_messages",
        );

      return res.json({
        success: true,
        products,
        username: account?.username || null,
        connected,
        messagingPermission,

        // Direct avtomatik javoblari hali ulanmagan.
        autoReplyEnabled: false,
      });
    }),
  );

  // Mahsulot yaratish yoki tahrirlash.
  // Bir xil ID qayta yuborilsa nusxa yaratilmaydi.
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

      const productRef = businessRef
        .collection("products")
        .doc(req.params.productId);

      const accepted = await db.runTransaction(
        async (transaction) => {
          const business = await transaction.get(
            businessRef,
          );

          const existing = await transaction.get(
            productRef,
          );

          const count =
            business.data()?.productCount || 0;

          if (
            !existing.exists &&
            count >= MAX_PRODUCTS
          ) {
            return false;
          }

          transaction.set(
            productRef,
            {
              ...product,
              updatedAt: FieldValue.serverTimestamp(),
              ...(!existing.exists
                ? {
                    createdAt:
                      FieldValue.serverTimestamp(),
                  }
                : {}),
            },
            { merge: true },
          );

          if (!existing.exists) {
            transaction.set(
              businessRef,
              {
                productCount: count + 1,
              },
              { merge: true },
            );
          }

          return true;
        },
      );

      if (!accepted) {
        return res.status(409).json({
          success: false,
          error: "CATALOG_FULL",
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

  // Faqat shu foydalanuvchining mahsulotini o'chirish.
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

      const productRef = businessRef
        .collection("products")
        .doc(req.params.productId);

      await db.runTransaction(async (transaction) => {
        const business = await transaction.get(
          businessRef,
        );

        const product = await transaction.get(
          productRef,
        );

        if (!product.exists) return;

        transaction.delete(productRef);

        transaction.set(
          businessRef,
          {
            productCount: Math.max(
              0,
              (business.data()?.productCount || 0) - 1,
            ),
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