import crypto from "node:crypto";
import { FieldValue } from "firebase-admin/firestore";

const BASE = "https://easyai-server.onrender.com";
const REDIRECT = `${BASE}/instagram/callback`;

const COOKIE = {
  httpOnly: true,
  secure: true,
  sameSite: "lax",
  path: "/instagram",
};

const hash = (value) =>
  crypto.createHash("sha256").update(value).digest("hex");

const nonce = () => crypto.randomBytes(32).toString("hex");

const isKey = (value) =>
  typeof value === "string" && /^[a-f0-9]{64}$/.test(value);

export function attachInstagram(app, db) {
  const identities = db.collection("instagramPrivateIdentities");
  const tickets = db.collection("instagramPrivateTickets");
  const states = db.collection("instagramPrivateStates");
  const connections = db.collection("instagramPrivateConnections");

  function settings() {
    const appId = process.env.INSTAGRAM_APP_ID?.trim();
    const appSecret = process.env.INSTAGRAM_APP_SECRET?.trim();

    const encryptionSecret =
      process.env.INSTAGRAM_TOKEN_ENCRYPTION_KEY?.trim();

    if (
      !appId ||
      !appSecret ||
      !encryptionSecret ||
      encryptionSecret.length < 32
    ) {
      throw new Error("INSTAGRAM_CONFIG_MISSING");
    }

    return {
      appId,
      appSecret,
      key: crypto
        .createHash("sha256")
        .update(encryptionSecret)
        .digest(),
    };
  }

  function seal(token, key, ownerId) {
    const iv = crypto.randomBytes(12);

    const cipher = crypto.createCipheriv(
      "aes-256-gcm",
      key,
      iv,
    );

    cipher.setAAD(Buffer.from(ownerId));

    const ciphertext = Buffer.concat([
      cipher.update(token, "utf8"),
      cipher.final(),
    ]);

    return {
      iv: iv.toString("base64"),
      ciphertext: ciphertext.toString("base64"),
      tag: cipher.getAuthTag().toString("base64"),
      version: 1,
    };
  }

  const wrap = (fn) => (req, res, next) =>
    Promise.resolve(fn(req, res)).catch(next);

  function credential(req) {
    const match = /^Bearer ([a-f0-9]{64})$/.exec(
      req.get("authorization") || "",
    );

    return match?.[1];
  }

  async function owner(req, res) {
    const token = credential(req);

    if (!token) {
      res.status(401).json({
        success: false,
        error: "INSTAGRAM_SESSION_INVALID",
      });

      return null;
    }

    const ownerId = hash(token);
    const identity = await identities.doc(ownerId).get();

    if (!identity.exists) {
      res.status(401).json({
        success: false,
        error: "INSTAGRAM_SESSION_INVALID",
      });

      return null;
    }

    return ownerId;
  }

  async function consume(ref) {
    return db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);

      if (
        !snapshot.exists ||
        snapshot.data().expiresAt.toMillis() <= Date.now()
      ) {
        return null;
      }

      const record = snapshot.data();

      transaction.delete(ref);

      return record;
    });
  }

  async function meta(url, options = {}) {
    const response = await fetch(url, {
      ...options,
      signal: AbortSignal.timeout(30000),
    });

    const data = await response.json();

    if (!response.ok || data.error) {
      throw new Error("INSTAGRAM_TOKEN_REQUEST_FAILED");
    }

    return data;
  }

  // Ilovaning maxfiy kalitini ro'yxatdan o'tkazish
  app.post(
    "/api/instagram/session",
    wrap(async (req, res) => {
      const token = credential(req);

      if (!token) {
        return res.status(400).json({
          success: false,
          error: "INVALID_SESSION_KEY",
        });
      }

      const ownerId = hash(token);

      await db.runTransaction(async (transaction) => {
        const ref = identities.doc(ownerId);
        const snapshot = await transaction.get(ref);

        if (!snapshot.exists) {
          transaction.create(ref, {
            createdAt: FieldValue.serverTimestamp(),
            connectionGeneration: 0,
          });
        }
      });

      return res
        .set("Cache-Control", "no-store")
        .json({ success: true });
    }),
  );

  // Ilova uchun bir martalik ulanish havolasi
  app.post(
    "/api/instagram/connect",
    wrap(async (req, res) => {
      const ownerId = await owner(req, res);

      if (!ownerId) return;

      try {
        settings();
      } catch {
        return res.status(503).json({
          success: false,
          error: "INSTAGRAM_CONFIG_MISSING",
        });
      }

      const ticket = nonce();
      const identityRef = identities.doc(ownerId);

      await db.runTransaction(async (transaction) => {
        const identity = await transaction.get(identityRef);

        const generation =
          (identity.data().connectionGeneration || 0) + 1;

        transaction.update(identityRef, {
          connectionGeneration: generation,
        });

        transaction.set(tickets.doc(hash(ticket)), {
          ownerId,
          generation,
          expiresAt: new Date(Date.now() + 5 * 60 * 1000),
        });
      });

      return res
        .set("Cache-Control", "no-store")
        .json({
          success: true,
          connectUrl: `${BASE}/instagram/login?ticket=${ticket}`,
        });
    }),
  );

  // Instagram ruxsat oynasiga yo'naltirish
  app.get(
    "/instagram/login",
    wrap(async (req, res) => {
      res.set({
        "Cache-Control": "no-store",
        "Referrer-Policy": "no-referrer",
      });

      const ticket = req.query.ticket;

      if (!isKey(ticket)) {
        return res.status(400).send(
          "Instagramga ulanishni EasyAI ilovasidan boshlang.",
        );
      }

      const config = settings();
      const record = await consume(tickets.doc(hash(ticket)));

      if (!record) {
        return res.status(403).send(
          "Ulanish havolasi eskirgan. Ilovadan qayta boshlang.",
        );
      }

      const state = nonce();

      await states.doc(hash(state)).set({
        ownerId: record.ownerId,
        generation: record.generation,
        expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      });

      res.cookie("ig_login_state", state, {
        ...COOKIE,
        maxAge: 10 * 60 * 1000,
      });

      const params = new URLSearchParams({
        client_id: config.appId,
        redirect_uri: REDIRECT,
        response_type: "code",
        scope: "instagram_business_basic",
        state,
      });

      return res.redirect(
        `https://www.instagram.com/oauth/authorize?${params}`,
      );
    }),
  );

  // Instagramdan qaytish va tokenni saqlash
  app.get(
    "/instagram/callback",
    wrap(async (req, res) => {
      res.set({
        "Cache-Control": "no-store",
        "Referrer-Policy": "no-referrer",
      });

      const state = req.query.state;

      const cookie = (req.headers.cookie || "")
        .split(";")
        .map((item) => item.trim())
        .find((item) => item.startsWith("ig_login_state="))
        ?.slice("ig_login_state=".length);

      if (!isKey(state) || state !== cookie) {
        return res.status(403).send(
          "Ulanish tekshiruvi o'tmadi. Ilovadan qayta boshlang.",
        );
      }

      const record = await consume(states.doc(hash(state)));

      res.clearCookie("ig_login_state", COOKIE);

      if (!record) {
        return res.status(403).send(
          "Ulanish muddati tugagan. Ilovadan qayta boshlang.",
        );
      }

      if (req.query.error) {
        return res.status(400).send(
          "Instagramga ulanish bekor qilindi.",
        );
      }

      if (
        typeof req.query.code !== "string" ||
        !req.query.code
      ) {
        return res.status(400).send(
          "Tasdiqlash kodi kelmadi.",
        );
      }

      try {
        const config = settings();
        const form = new FormData();

        const fields = {
          client_id: config.appId,
          client_secret: config.appSecret,
          grant_type: "authorization_code",
          redirect_uri: REDIRECT,
          code: req.query.code,
        };

        for (const [name, value] of Object.entries(fields)) {
          form.set(name, value);
        }

        const result = await meta(
          "https://api.instagram.com/oauth/access_token",
          {
            method: "POST",
            body: form,
          },
        );

        const short = Array.isArray(result.data)
          ? result.data.length === 1
            ? result.data[0]
            : null
          : result;

        if (!short?.access_token || !short?.user_id) {
          throw new Error("INVALID_TOKEN_RESPONSE");
        }

        const url = new URL(
          "https://graph.instagram.com/access_token",
        );

        url.search = new URLSearchParams({
          grant_type: "ig_exchange_token",
          client_secret: config.appSecret,
          access_token: short.access_token,
        }).toString();

        const long = await meta(url);

        if (
          !long.access_token ||
          !Number.isFinite(long.expires_in) ||
          long.expires_in <= 0
        ) {
          throw new Error("INVALID_LONG_TOKEN");
        }

        const account = {
          instagramUserId: String(short.user_id),

          permissions:
            typeof short.permissions === "string"
              ? short.permissions.split(",")
              : Array.isArray(short.permissions)
                ? short.permissions
                : [],

          token: seal(
            long.access_token,
            config.key,
            record.ownerId,
          ),

          expiresAt: new Date(
            Date.now() + long.expires_in * 1000,
          ),

          connectedAt: FieldValue.serverTimestamp(),
        };

        await db.runTransaction(async (transaction) => {
          const identity = await transaction.get(
            identities.doc(record.ownerId),
          );

          if (
            !identity.exists ||
            identity.data().connectionGeneration !==
              record.generation
          ) {
            throw new Error("CONNECTION_SUPERSEDED");
          }

          transaction.set(
            connections.doc(record.ownerId),
            account,
          );
        });

        return res.type("text/plain").send(
          "Instagram hisobi saqlandi! EasyAI ilovasiga qaytib, ulanish holatini tekshiring.",
        );
      } catch (error) {
        console.error(
          "INSTAGRAM CONNECT FAILED:",
          error?.message === "CONNECTION_SUPERSEDED"
            ? "CONNECTION_SUPERSEDED"
            : "TOKEN_OR_STORAGE_FAILED",
        );

        return res.status(502).send(
          "Instagram hisobini saqlashda xato. Ilovadan qayta urinib ko'ring.",
        );
      }
    }),
  );

  // Faqat shu ilovaning ulanish holatini qaytarish
  app.get(
    "/api/instagram/status",
    wrap(async (req, res) => {
      const ownerId = await owner(req, res);

      if (!ownerId) return;

      const snapshot = await connections.doc(ownerId).get();
      const account = snapshot.data();

      const expired = account
        ? account.expiresAt.toMillis() <= Date.now()
        : false;

      return res
        .set("Cache-Control", "no-store")
        .json({
          success: true,
          connected: snapshot.exists && !expired,
          needsReconnect: expired,
          instagramUserId: account?.instagramUserId || null,
          expiresAt:
            account?.expiresAt.toDate().toISOString() || null,
        });
    }),
  );

  // Serverdagi ulanishni o'chirish
  app.delete(
    "/api/instagram/connection",
    wrap(async (req, res) => {
      const ownerId = await owner(req, res);

      if (!ownerId) return;

      await db.runTransaction(async (transaction) => {
        const ref = identities.doc(ownerId);
        const identity = await transaction.get(ref);

        transaction.update(ref, {
          connectionGeneration:
            (identity.data().connectionGeneration || 0) + 1,
        });

        transaction.delete(connections.doc(ownerId));
      });

      return res.json({ success: true });
    }),
  );
}