import crypto from "node:crypto";
import { FieldValue } from "firebase-admin/firestore";
import multer from "multer";
import path from "node:path";
import { open, unlink } from "node:fs/promises";

import {
  attachInstagramBusiness,
} from "./instagram_business_server.js";

import {
  startInstagramMessageWorker,
} from "./instagram_message_worker.js";

const BASE = "https://easyai-server.onrender.com";
const REDIRECT = `${BASE}/instagram/callback`;
const GRAPH = "https://graph.instagram.com/v25.0";

const COOKIE = {
  httpOnly: true,
  secure: true,
  sameSite: "lax",
  path: "/instagram",
};

const hash = (value) =>
  crypto.createHash("sha256").update(value).digest("hex");

const nonce = () =>
  crypto.randomBytes(32).toString("hex");

const isKey = (value) =>
  typeof value === "string" &&
  /^[a-f0-9]{64}$/.test(value);

const isId = (value) =>
  typeof value === "string" &&
  /^\d+$/.test(value);

const numericId = (value) =>
  isId(value)
    ? value
    : Number.isSafeInteger(value) && value > 0
      ? String(value)
      : null;

export function attachInstagram(
  app,
  db,
  { videosDirectory },
) {
  const businessService = attachInstagramBusiness(
    app,
    db,
    { owner },
  );

  startInstagramMessageWorker(db, {
    sendReply: sendInstagramReply,
  });

  const identities = db.collection(
    "instagramPrivateIdentities",
  );
  const tickets = db.collection(
    "instagramPrivateTickets",
  );
  const states = db.collection(
    "instagramPrivateStates",
  );
  const connections = db.collection(
    "instagramPrivateConnections",
  );
  const reelJobs = db.collection(
    "instagramPrivateReelJobs",
  );

  const activeUploads = new Set();

  const wrap = (fn) => (req, res, next) =>
    Promise.resolve(fn(req, res)).catch(next);

  const expired = (account) =>
    !account ||
    !account.expiresAt ||
    account.expiresAt.toMillis() <= Date.now();

  const canPublish = (account) =>
    Array.isArray(account.permissions) &&
    account.permissions.includes(
      "instagram_business_content_publish",
    );

  function settings() {
    const appId = process.env.INSTAGRAM_APP_ID?.trim();
    const appSecret =
      process.env.INSTAGRAM_APP_SECRET?.trim();
    const secret =
      process.env.INSTAGRAM_TOKEN_ENCRYPTION_KEY?.trim();

    if (
      !appId ||
      !appSecret ||
      !secret ||
      secret.length < 32
    ) {
      throw new Error("INSTAGRAM_CONFIG_MISSING");
    }

    return {
      appId,
      appSecret,
      key: crypto
        .createHash("sha256")
        .update(secret)
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

  function openInstagramToken(account, ownerId) {
    const saved = account.token;

    if (!saved || saved.version !== 1) {
      throw new Error("INVALID_STORED_TOKEN");
    }

    const decipher = crypto.createDecipheriv(
      "aes-256-gcm",
      settings().key,
      Buffer.from(saved.iv, "base64"),
    );

    decipher.setAAD(Buffer.from(ownerId));

    decipher.setAuthTag(
      Buffer.from(saved.tag, "base64"),
    );

    return Buffer.concat([
      decipher.update(
        Buffer.from(saved.ciphertext, "base64"),
      ),
      decipher.final(),
    ]).toString("utf8");
  }

  async function sendInstagramReply(inboxId) {
    if (!isKey(inboxId)) {
      throw new Error("INVALID_INBOX_ID");
    }

    const inboxRef = db
      .collection("instagramPrivateMessageInbox")
      .doc(inboxId);

    const claimed = await db.runTransaction(async (tx) => {
      const savedMessage = await tx.get(inboxRef);
      const message = savedMessage.data();

      // Do not repeat an already started send.
      if (!message || message.state !== "reply_ready") {
        return null;
      }

      const ownerId = message.replyOwnerId;

      if (
        !isKey(ownerId) ||
        !isId(message.instagramUserId) ||
        !isId(message.senderId) ||
        message.instagramUserId === message.senderId ||
        typeof message.replyText !== "string" ||
        !message.replyText.trim() ||
        message.replyText.length > 1000
      ) {
        tx.update(inboxRef, {
          state: "reply_failed",
          replyError: "INVALID_REPLY_DATA",
        });

        return null;
      }

      const savedAccount = await tx.get(
        connections.doc(ownerId),
      );

      const savedBusiness = await tx.get(
        db.collection("instagramPrivateBusinesses")
          .doc(ownerId),
      );

      const matchingAccounts = await tx.get(
        connections
          .where(
            "instagramUserId",
            "==",
            message.instagramUserId,
          )
          .limit(2),
      );

      const account = savedAccount.data();
      const business = savedBusiness.data();

      const enabledAt =
        typeof business?.autoReplyEnabledAt?.toMillis ===
        "function"
          ? business.autoReplyEnabledAt.toMillis()
          : null;

      const now = Date.now();
      let reason = null;

      if (
        !account ||
        account.profileVerified !== true ||
        typeof account.expiresAt?.toMillis !== "function" ||
        account.expiresAt.toMillis() <= now ||
        account.instagramUserId !== message.instagramUserId
      ) {
        reason = "INSTAGRAM_RECONNECT_REQUIRED";
      } else if (
        !Array.isArray(account.permissions) ||
        !account.permissions.includes(
          "instagram_business_manage_messages",
        )
      ) {
        reason = "INSTAGRAM_MESSAGING_PERMISSION_REQUIRED";
      } else if (
        matchingAccounts.size !== 1 ||
        matchingAccounts.docs[0].id !== ownerId
      ) {
        reason = "INSTAGRAM_ACCOUNT_OWNER_AMBIGUOUS";
      } else if (
        business?.autoReplyEnabled !== true ||
        business?.autoReplyInstagramUserId !==
          message.instagramUserId ||
        enabledAt === null
      ) {
        reason = "AUTO_REPLY_DISABLED";
      } else if (
        !Number.isSafeInteger(message.timestamp) ||
        message.timestamp < enabledAt ||
        message.timestamp > now + 60 * 1000 ||
        now - message.timestamp >= 24 * 60 * 60 * 1000
      ) {
        reason = "MESSAGE_OUTSIDE_REPLY_WINDOW";
      }

      if (reason) {
        tx.update(inboxRef, {
          state: "reply_skipped",
          replyError: reason,
          replyUpdatedAt: FieldValue.serverTimestamp(),
        });

        return null;
      }

      tx.update(inboxRef, {
        state: "sending",
        replyAttemptAt: FieldValue.serverTimestamp(),
      });

      return {
        ownerId,
        account,
        senderId: message.senderId,
        replyText: message.replyText.trim(),
      };
    });

    if (!claimed) return null;

    let accessToken;
    let requestStarted = false;

    try {
      accessToken = openInstagramToken(
        claimed.account,
        claimed.ownerId,
      );

      requestStarted = true;

      const result = await meta(
        `${GRAPH}/${claimed.account.instagramUserId}/messages`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            recipient: {
              id: claimed.senderId,
            },
            message: {
              text: claimed.replyText,
            },
          }),
        },
      );

      if (
        typeof result.message_id !== "string" ||
        !result.message_id ||
        result.recipient_id !== claimed.senderId
      ) {
        throw new Error("INVALID_SEND_RESPONSE");
      }

      await inboxRef.update({
        state: "replied",
        replyMessageId: result.message_id,
        repliedAt: FieldValue.serverTimestamp(),
      });

      console.info("Instagram reply: sent");

      return {
        messageId: result.message_id,
      };
    } catch (error) {
      logError(
        "INSTAGRAM REPLY ERROR:",
        error,
        [accessToken],
      );

      const clearlyRejected =
        Number.isInteger(error.httpStatus) &&
        error.httpStatus >= 400 &&
        error.httpStatus < 500;

      await inboxRef.update({
        state:
          requestStarted && !clearlyRejected
            ? "reply_needs_check"
            : "reply_failed",
        replyError: "INSTAGRAM_REPLY_FAILED",
        replyHttpStatus: error.httpStatus || null,
        replyMetaCode: error.metaCode || null,
        replyUpdatedAt: FieldValue.serverTimestamp(),
      }).catch(() => {
        console.error(
          "Instagram reply: result could not be saved",
        );
      });

      return null;
    }
  }

  function credential(req) {
    return /^Bearer ([a-f0-9]{64})$/.exec(
      req.get("authorization") || "",
    )?.[1];
  }

  const trustedOwner = Symbol("internalInstagramOwner");

  async function owner(req, res) {
    if (req[trustedOwner]) {
      return req[trustedOwner];
    }

    const token = credential(req);
    const ownerId = token ? hash(token) : null;

    if (
      !ownerId ||
      !(await identities.doc(ownerId).get()).exists
    ) {
      res.status(401).json({
        success: false,
        error: "INSTAGRAM_SESSION_INVALID",
      });

      return null;
    }

    return ownerId;
  }

  async function consume(ref) {
    return db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);

      if (
        !snap.exists ||
        snap.data().expiresAt.toMillis() <= Date.now()
      ) {
        return null;
      }

      tx.delete(ref);

      return snap.data();
    });
  }

  function logError(label, error, secrets = []) {
    let message = String(
      error.metaMessage ||
      error.message ||
      "Request failed",
    );

    for (const secret of secrets.filter(Boolean)) {
      message = message.replaceAll(
        secret,
        "[REDACTED]",
      );
    }

    message = message.replace(
      /(access_token|client_secret)=([^&\s]+)/gi,
      "$1=[REDACTED]",
    );

    console.error(
      label,
      JSON.stringify({
        httpStatus: error.httpStatus || null,
        code: error.metaCode || null,
        subcode: error.metaSubcode || null,
        type: error.metaType || error.name || null,
        message: message.slice(0, 1500),
      }),
    );
  }

  async function meta(url, options = {}) {
    const response = await fetch(url, {
      ...options,
      signal: AbortSignal.timeout(30000),
    });

    const data = await response.json();

    if (!response.ok || data.error) {
      const error = new Error(
        "INSTAGRAM_META_REQUEST_FAILED",
      );

      error.httpStatus = response.status;
      error.metaCode = data.error?.code;
      error.metaSubcode = data.error?.error_subcode;
      error.metaType = data.error?.type;
      error.metaMessage = data.error?.message;

      throw error;
    }

    return data;
  }

  async function profile(accessToken) {
    const url = new URL(`${GRAPH}/me`);

    url.searchParams.set(
      "fields",
      "user_id,username",
    );

    const result = await meta(url, {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    });

    const user = Array.isArray(result.data)
      ? result.data.length === 1
        ? result.data[0]
        : null
      : result;

    const instagramUserId = numericId(user?.user_id);

    if (
      !instagramUserId ||
      typeof user?.username !== "string" ||
      !user.username
    ) {
      throw new Error(
        "INSTAGRAM_PROFILE_ID_MISSING_OR_UNSAFE",
      );
    }

    return {
      instagramUserId,
      username: user.username,
    };
  }

  const videoUpload = multer({
    storage: multer.diskStorage({
      destination: videosDirectory,
      filename: (req, file, done) =>
        done(null, `instagram-${nonce()}.mp4`),
    }),
    limits: {
      fileSize: 100 * 1024 * 1024,
      files: 1,
      fields: 0,
      parts: 2,
    },
  }).single("video");

  app.post(
    "/api/instagram/videos/upload",
    async (req, res, next) => {
      try {
        res.set("Cache-Control", "no-store");

        const ownerId = await owner(req, res);

        if (!ownerId) return;

        const account = (
          await connections.doc(ownerId).get()
        ).data();

        if (expired(account)) {
          return res.status(409).json({
            success: false,
            error: "INSTAGRAM_RECONNECT_REQUIRED",
          });
        }

        if (activeUploads.has(ownerId)) {
          return res.status(429).json({
            success: false,
            error: "VIDEO_UPLOAD_BUSY",
          });
        }

        activeUploads.add(ownerId);

        const release = () =>
          activeUploads.delete(ownerId);

        res.once("finish", release);
        res.once("close", release);

        next();
      } catch (error) {
        next(error);
      }
    },
    (req, res) => {
      videoUpload(req, res, async (uploadError) => {
        const remove = async () => {
          if (req.file?.path) {
            await unlink(req.file.path).catch(() => {});
          }
        };

        try {
          if (uploadError) {
            await remove();

            return res.status(400).json({
              success: false,
              error:
                uploadError.code === "LIMIT_FILE_SIZE"
                  ? "VIDEO_TOO_LARGE"
                  : "INVALID_VIDEO_UPLOAD",
            });
          }

          if (!req.file || req.file.size < 16) {
            await remove();

            return res.status(400).json({
              success: false,
              error: "INVALID_MP4_VIDEO",
            });
          }

          const file = await open(req.file.path, "r");
          const header = Buffer.alloc(12);

          try {
            await file.read(
              header,
              0,
              header.length,
              0,
            );
          } finally {
            await file.close();
          }

          const boxSize = header.readUInt32BE(0);
          const brand = header.toString("ascii", 8, 12);

          if (
            header.toString("ascii", 4, 8) !== "ftyp" ||
            boxSize < 16 ||
            boxSize > req.file.size ||
            ["qt  ", "heic", "heix", "avif", "avis"]
              .includes(brand)
          ) {
            await remove();

            return res.status(400).json({
              success: false,
              error: "INVALID_MP4_VIDEO",
            });
          }

          res.json({
            success: true,
            videoUrl:
              `${BASE}/videos/${path.basename(req.file.path)}`,
          });
        } catch (error) {
          await remove();

          logError(
            "INSTAGRAM UPLOAD ERROR:",
            error,
          );

          if (!res.headersSent) {
            res.status(500).json({
              success: false,
              error: "VIDEO_UPLOAD_FAILED",
            });
          }
        }
      });
    },
  );

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

      const ref = identities.doc(hash(token));

      await db.runTransaction(async (tx) => {
        if (!(await tx.get(ref)).exists) {
          tx.create(ref, {
            createdAt: FieldValue.serverTimestamp(),
            connectionGeneration: 0,
          });
        }
      });

      res.set("Cache-Control", "no-store").json({
        success: true,
      });
    }),
  );

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
      const ref = identities.doc(ownerId);

      await db.runTransaction(async (tx) => {
        const identity = await tx.get(ref);

        const generation =
          (identity.data().connectionGeneration || 0) + 1;

        tx.update(ref, {
          connectionGeneration: generation,
        });

        tx.set(tickets.doc(hash(ticket)), {
          ownerId,
          generation,
          expiresAt: new Date(
            Date.now() + 5 * 60 * 1000,
          ),
        });
      });

      res.set("Cache-Control", "no-store").json({
        success: true,
        connectUrl:
          `${BASE}/instagram/login?ticket=${ticket}`,
      });
    }),
  );

  app.get(
    "/instagram/login",
    wrap(async (req, res) => {
      res.set({
        "Cache-Control": "no-store",
        "Referrer-Policy": "no-referrer",
      });

      if (!isKey(req.query.ticket)) {
        return res.status(400).send(
          "Start Instagram connection from EasyAI. / " +
          "EasyAI аркылуу баштаңыз. / " +
          "Начните подключение в EasyAI. / " +
          "EasyAI üzerinden başlayın.",
        );
      }

      const config = settings();

      const record = await consume(
        tickets.doc(hash(req.query.ticket)),
      );

      if (!record) {
        return res.status(403).send(
          "Link expired. / " +
          "Шилтеменин мөөнөтү бүттү. / " +
          "Ссылка истекла. / " +
          "Bağlantının süresi doldu.",
        );
      }

      const state = nonce();

      await states.doc(hash(state)).set({
        ownerId: record.ownerId,
        generation: record.generation,
        expiresAt: new Date(
          Date.now() + 10 * 60 * 1000,
        ),
      });

      res.cookie("ig_login_state", state, {
        ...COOKIE,
        maxAge: 10 * 60 * 1000,
      });

      const params = new URLSearchParams({
        client_id: config.appId,
        redirect_uri: REDIRECT,
        response_type: "code",
        force_reauth: "true",
        scope: [
          "instagram_business_basic",
          "instagram_business_content_publish",
          "instagram_business_manage_messages",
        ].join(","),
        state,
      });

      res.redirect(
        `https://www.instagram.com/oauth/authorize?${params}`,
      );
    }),
  );

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
        .find(
          (item) => item.startsWith("ig_login_state="),
        )
        ?.slice("ig_login_state=".length);

      const retryMessage =
        "Reconnect from EasyAI. / " +
        "EasyAI аркылуу кайра туташыңыз. / " +
        "Подключитесь заново в EasyAI. / " +
        "EasyAI üzerinden yeniden bağlanın.";

      if (!isKey(state) || state !== cookie) {
        return res.status(403).send(retryMessage);
      }

      const record = await consume(
        states.doc(hash(state)),
      );

      res.clearCookie("ig_login_state", COOKIE);

      if (!record) {
        return res.status(403).send(retryMessage);
      }

      if (
        req.query.error ||
        typeof req.query.code !== "string" ||
        !req.query.code
      ) {
        return res.status(400).send(retryMessage);
      }

      const secrets = [];

      try {
        const config = settings();

        secrets.push(config.appSecret);

        const form = new FormData();

        for (const [name, value] of Object.entries({
          client_id: config.appId,
          client_secret: config.appSecret,
          grant_type: "authorization_code",
          redirect_uri: REDIRECT,
          code: req.query.code,
        })) {
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

        if (
          typeof short?.access_token !== "string" ||
          !short.access_token
        ) {
          throw new Error("INVALID_TOKEN_RESPONSE");
        }

        secrets.push(short.access_token);

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
          typeof long.access_token !== "string" ||
          !long.access_token ||
          !Number.isFinite(long.expires_in) ||
          long.expires_in <= 0
        ) {
          throw new Error("INVALID_LONG_TOKEN");
        }

        secrets.push(long.access_token);

        const verifiedProfile = await profile(
          long.access_token,
        );

        const permissions =
          typeof short.permissions === "string"
            ? short.permissions
                .split(",")
                .map((value) => value.trim())
            : Array.isArray(short.permissions)
              ? short.permissions
              : [];

        if (
          !permissions.includes(
            "instagram_business_content_publish",
          )
        ) {
          throw new Error(
            "INSTAGRAM_PUBLISH_PERMISSION_REQUIRED",
          );
        }

        const account = {
          ...verifiedProfile,
          permissions,
          token: seal(
            long.access_token,
            config.key,
            record.ownerId,
          ),
          profileVerified: true,
          expiresAt: new Date(
            Date.now() + long.expires_in * 1000,
          ),
          connectedAt: FieldValue.serverTimestamp(),
        };

        await db.runTransaction(async (tx) => {
          const identity = await tx.get(
            identities.doc(record.ownerId),
          );

          if (
            !identity.exists ||
            identity.data().connectionGeneration !==
              record.generation
          ) {
            throw new Error("CONNECTION_SUPERSEDED");
          }

          tx.set(
            connections.doc(record.ownerId),
            account,
          );
        });

        console.info(
          "INSTAGRAM PROFILE VERIFIED:",
          JSON.stringify({
            instagramUserId:
              verifiedProfile.instagramUserId,
            publishPermission: true,
          }),
        );

        res.type("text/plain").send(
          "Instagram connected. Return to EasyAI.\n" +
          "Instagram туташты. EasyAI колдонмосуна кайтыңыз.\n" +
          "Instagram подключён. Вернитесь в EasyAI.\n" +
          "Instagram bağlandı. EasyAI uygulamasına dönün.",
        );
      } catch (error) {
        logError(
          "INSTAGRAM CONNECT ERROR:",
          error,
          secrets,
        );

        res.status(502).type("text/plain").send(
          "Instagram connection could not be verified.\n" +
          "Instagram байланышы текшерилген жок.\n" +
          "Не удалось проверить подключение Instagram.\n" +
          "Instagram bağlantısı doğrulanamadı.\n\n" +
          retryMessage,
        );
      }
    }),
  );

  app.get(
    "/api/instagram/status",
    wrap(async (req, res) => {
      const ownerId = await owner(req, res);

      if (!ownerId) return;

      const account = (
        await connections.doc(ownerId).get()
      ).data();

      res.set("Cache-Control", "no-store").json({
        success: true,
        connected:
          !!account &&
          !expired(account) &&
          account.profileVerified === true,
        needsReconnect:
          !!account &&
          (
            expired(account) ||
            account.profileVerified !== true
          ),
        instagramUserId:
          account?.instagramUserId || null,
        username: account?.username || null,
        expiresAt:
          account?.expiresAt?.toDate().toISOString() || null,
      });
    }),
  );

  app.delete(
    "/api/instagram/connection",
    wrap(async (req, res) => {
      const ownerId = await owner(req, res);

      if (!ownerId) return;

      await db.runTransaction(async (tx) => {
        const ref = identities.doc(ownerId);
        const identity = await tx.get(ref);

        tx.update(ref, {
          connectionGeneration:
            (identity.data().connectionGeneration || 0) + 1,
        });

        tx.delete(connections.doc(ownerId));
      });

      res.json({
        success: true,
      });
    }),
  );

  const prepareReel = wrap(async (req, res) => {
    res.set("Cache-Control", "no-store");

    const ownerId = await owner(req, res);

    if (!ownerId) return;

    const {
      requestId,
      videoUrl,
      caption = "",
    } = req.body || {};

    if (
      !isKey(requestId) ||
      typeof videoUrl !== "string" ||
      typeof caption !== "string" ||
      caption.length > 2200
    ) {
      return res.status(400).json({
        success: false,
        error: "INVALID_REEL_REQUEST",
      });
    }

    let url;

    try {
      url = new URL(videoUrl);
    } catch {
      return res.status(400).json({
        success: false,
        error: "INVALID_VIDEO_URL",
      });
    }

    if (
      url.origin !== BASE ||
      url.username ||
      url.password ||
      url.search ||
      url.hash ||
      !/^\/videos\/[a-zA-Z0-9_-]+\.mp4$/.test(
        url.pathname,
      )
    ) {
      return res.status(400).json({
        success: false,
        error: "USE_EASYAI_VIDEO_URL",
      });
    }

    const account = (
      await connections.doc(ownerId).get()
    ).data();

    if (
      expired(account) ||
      account.profileVerified !== true
    ) {
      return res.status(409).json({
        success: false,
        error: "INSTAGRAM_RECONNECT_REQUIRED",
      });
    }

    if (!canPublish(account)) {
      return res.status(403).json({
        success: false,
        error: "INSTAGRAM_PUBLISH_PERMISSION_REQUIRED",
      });
    }

    const jobId = hash(`${ownerId}:${requestId}`);
    const jobRef = reelJobs.doc(jobId);

    const fingerprint = hash(
      JSON.stringify([
        url.href,
        caption,
        account.instagramUserId,
      ]),
    );

    const existing = await db.runTransaction(
      async (tx) => {
        const job = await tx.get(jobRef);

        if (job.exists) {
          return job.data();
        }

        tx.create(jobRef, {
          ownerId,
          instagramUserId: account.instagramUserId,
          fingerprint,
          state: "creating",
          createdAt: FieldValue.serverTimestamp(),
        });

        return null;
      },
    );

    if (existing) {
      if (existing.fingerprint !== fingerprint) {
        return res.status(409).json({
          success: false,
          error: "REQUEST_ID_ALREADY_USED",
        });
      }

      return res.json({
        success: existing.state === "processing",
        jobId,
        state: existing.state,
      });
    }

    let accessToken;

    try {
      accessToken = openInstagramToken(
        account,
        ownerId,
      );

      const body = new URLSearchParams({
        media_type: "REELS",
        video_url: url.href,
        caption,
        share_to_feed: "true",
      });

      const result = await meta(
        `${GRAPH}/${account.instagramUserId}/media`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type":
              "application/x-www-form-urlencoded",
          },
          body,
        },
      );

      const containerId = numericId(result.id);

      if (!containerId) {
        throw new Error("INVALID_CONTAINER_ID");
      }

      await jobRef.update({
        containerId,
        state: "processing",
        updatedAt: FieldValue.serverTimestamp(),
      });

      res.json({
        success: true,
        jobId,
        state: "processing",
      });
    } catch (error) {
      logError(
        "INSTAGRAM PREPARE ERROR:",
        error,
        [accessToken],
      );

      await jobRef.update({
        state: "needs_check",
        updatedAt: FieldValue.serverTimestamp(),
      });

      res.status(502).json({
        success: false,
        jobId,
        error: "INSTAGRAM_PREPARE_NEEDS_CHECK",
      });
    }
  });

  app.post(
    "/api/instagram/reels/prepare",
    prepareReel,
  );

  const reelStatus = wrap(async (req, res) => {
    res.set("Cache-Control", "no-store");

    const ownerId = await owner(req, res);

    if (!ownerId) return;

    if (!isKey(req.params.jobId)) {
      return res.status(400).json({
        success: false,
        error: "INVALID_JOB_ID",
      });
    }

    const jobRef = reelJobs.doc(req.params.jobId);
    const job = (await jobRef.get()).data();

    if (!job || job.ownerId !== ownerId) {
      return res.status(404).json({
        success: false,
        error: "REEL_NOT_FOUND",
      });
    }

    if (!job.containerId || job.state === "published") {
      return res.json({
        success: true,
        jobId: req.params.jobId,
        state: job.state,
        mediaId: job.mediaId || null,
      });
    }

    const account = (
      await connections.doc(ownerId).get()
    ).data();

    if (
      expired(account) ||
      account.instagramUserId !== job.instagramUserId
    ) {
      return res.status(409).json({
        success: false,
        error: "INSTAGRAM_RECONNECT_REQUIRED",
      });
    }

    let accessToken;

    try {
      accessToken = openInstagramToken(
        account,
        ownerId,
      );

      const url = new URL(
        `${GRAPH}/${job.containerId}`,
      );

      url.searchParams.set(
        "fields",
        "status_code",
      );

      const result = await meta(url, {
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      });

      if (
        ![
          "IN_PROGRESS",
          "FINISHED",
          "ERROR",
          "EXPIRED",
          "PUBLISHED",
        ].includes(result.status_code)
      ) {
        throw new Error("INVALID_CONTAINER_STATUS");
      }

      await jobRef.update({
        containerStatus: result.status_code,
        checkedAt: FieldValue.serverTimestamp(),
      });

      res.json({
        success: true,
        jobId: req.params.jobId,
        state: job.state,
        containerStatus: result.status_code,
        readyToPublish:
          job.state === "processing" &&
          result.status_code === "FINISHED",
      });
    } catch (error) {
      logError(
        "INSTAGRAM STATUS ERROR:",
        error,
        [accessToken],
      );

      res.status(502).json({
        success: false,
        error: "INSTAGRAM_STATUS_FAILED",
      });
    }
  });

  app.get(
    "/api/instagram/reels/:jobId/status",
    reelStatus,
  );

  const publishReel = wrap(async (req, res) => {
    res.set("Cache-Control", "no-store");

    const ownerId = await owner(req, res);

    if (!ownerId) return;

    if (
      !isKey(req.params.jobId) ||
      req.body?.confirm !== true
    ) {
      return res.status(400).json({
        success: false,
        error: "PUBLISH_CONFIRMATION_REQUIRED",
      });
    }

    const jobRef = reelJobs.doc(req.params.jobId);

    const claimed = await db.runTransaction(
      async (tx) => {
        const job = (
          await tx.get(jobRef)
        ).data();

        const account = (
          await tx.get(connections.doc(ownerId))
        ).data();

        if (!job || job.ownerId !== ownerId) {
          return {
            error: "REEL_NOT_FOUND",
            status: 404,
          };
        }

        if (job.state === "published") {
          return {
            published: true,
            mediaId: job.mediaId,
          };
        }

        if (
          expired(account) ||
          account.instagramUserId !== job.instagramUserId
        ) {
          return {
            error: "INSTAGRAM_RECONNECT_REQUIRED",
            status: 409,
          };
        }

        if (!canPublish(account)) {
          return {
            error: "INSTAGRAM_PUBLISH_PERMISSION_REQUIRED",
            status: 403,
          };
        }

        if (
          !job.containerId ||
          job.state !== "processing"
        ) {
          return {
            error: "REEL_NOT_READY_OR_ALREADY_SUBMITTED",
            status: 409,
          };
        }

        tx.update(jobRef, {
          state: "publishing",
          updatedAt: FieldValue.serverTimestamp(),
        });

        return { job, account };
      },
    );

    if (claimed.error) {
      return res.status(claimed.status).json({
        success: false,
        error: claimed.error,
      });
    }

    if (claimed.published) {
      return res.json({
        success: true,
        state: "published",
        mediaId: claimed.mediaId,
      });
    }

    let publishStarted = false;
    let accessToken;

    try {
      accessToken = openInstagramToken(
        claimed.account,
        ownerId,
      );

      const headers = {
        Authorization: `Bearer ${accessToken}`,
      };

      const url = new URL(
        `${GRAPH}/${claimed.job.containerId}`,
      );

      url.searchParams.set(
        "fields",
        "status_code",
      );

      const status = await meta(url, { headers });

      if (status.status_code !== "FINISHED") {
        await jobRef.update({
          state: "processing",
          containerStatus:
            status.status_code || "UNKNOWN",
          updatedAt: FieldValue.serverTimestamp(),
        });

        return res.status(409).json({
          success: false,
          error: "REEL_NOT_READY",
          containerStatus:
            status.status_code || "UNKNOWN",
        });
      }

      const body = new URLSearchParams({
        creation_id: claimed.job.containerId,
      });

      publishStarted = true;

      const result = await meta(
        `${GRAPH}/${claimed.job.instagramUserId}/media_publish`,
        {
          method: "POST",
          headers: {
            ...headers,
            "Content-Type":
              "application/x-www-form-urlencoded",
          },
          body,
        },
      );

      const mediaId = numericId(result.id);

      if (!mediaId) {
        throw new Error("INVALID_PUBLISHED_MEDIA_ID");
      }

      await jobRef.update({
        state: "published",
        mediaId,
        publishedAt: FieldValue.serverTimestamp(),
      });

      res.json({
        success: true,
        jobId: req.params.jobId,
        state: "published",
        mediaId,
      });
    } catch (error) {
      logError(
        "INSTAGRAM PUBLISH ERROR:",
        error,
        [accessToken],
      );

      await jobRef.update({
        state: publishStarted
          ? "publish_needs_check"
          : "processing",
        updatedAt: FieldValue.serverTimestamp(),
      });

      res.status(502).json({
        success: false,
        jobId: req.params.jobId,
        error: publishStarted
          ? "INSTAGRAM_PUBLISH_NEEDS_CHECK"
          : "INSTAGRAM_STATUS_FAILED",
      });
    }
  });

  app.post(
    "/api/instagram/reels/:jobId/publish",
    publishReel,
  );

  // Internal calls use the same ownership and duplicate checks.
  // The trusted symbol cannot be supplied through HTTP.
  async function invoke(
    handler,
    ownerId,
    body = {},
    params = {},
  ) {
    let result;
    let status = 200;
    let raised;

    const req = {
      [trustedOwner]: ownerId,
      body,
      params,
      get: () => "",
    };

    const res = {
      set() {
        return this;
      },

      status(value) {
        status = value;
        return this;
      },

      json(value) {
        result = value;
        return this;
      },
    };

    await handler(req, res, (error) => {
      raised = error;
    });

    if (raised) {
      throw raised;
    }

    if (
      status >= 400 ||
      result?.success === false
    ) {
      const error = new Error(
        result?.error || "INSTAGRAM_OPERATION_FAILED",
      );

      error.code = result?.error;
      error.status = status;
      error.result = result;

      throw error;
    }

    return result;
  }

  return {
    async account(ownerId) {
      const account = (
        await connections.doc(ownerId).get()
      ).data();

      if (
        expired(account) ||
        account.profileVerified !== true
      ) {
        throw Object.assign(
          new Error("INSTAGRAM_RECONNECT_REQUIRED"),
          {
            code: "INSTAGRAM_RECONNECT_REQUIRED",
          },
        );
      }

      return {
        id: account.instagramUserId,
        username: account.username,
        canPublish: canPublish(account),
      };
    },

    prepare: (ownerId, body) =>
      invoke(prepareReel, ownerId, body),

    status: (ownerId, jobId) =>
      invoke(
        reelStatus,
        ownerId,
        {},
        { jobId },
      ),

    publish: (ownerId, jobId) =>
      invoke(
        publishReel,
        ownerId,
        { confirm: true },
        { jobId },
      ),

    business: (ownerId, enabled) =>
      businessService.setAutoReply(
        ownerId,
        enabled,
      ),
  };
}