import crypto from "node:crypto";
import { FieldValue } from "firebase-admin/firestore";

export function attachInstagramWebhook(app, db) {
  const inbox = db.collection("instagramPrivateMessageInbox");

  app.post("/instagram/webhook", async (req, res) => {
    const secret =
      (process.env.INSTAGRAM_WEBHOOK_APP_SECRET || "").trim();

    if (!secret) {
      console.error("Instagram webhook: app secret missing");
      return res.sendStatus(503);
    }

    const raw = req.instagramRawBody;
    const signature = req.get("x-hub-signature-256");

    if (
      !Buffer.isBuffer(raw) ||
      typeof signature !== "string" ||
      !/^sha256=[a-f0-9]{64}$/i.test(signature)
    ) {
      return res.sendStatus(403);
    }

    const expected = crypto
      .createHmac("sha256", secret)
      .update(raw)
      .digest();

    const received = Buffer.from(signature.slice(7), "hex");

    if (
      received.length !== expected.length ||
      !crypto.timingSafeEqual(received, expected)
    ) {
      console.error("Instagram webhook: invalid signature");
      return res.sendStatus(403);
    }

    if (req.body?.object !== "instagram") {
      return res.sendStatus(200);
    }

    const entries = req.body.entry;

    if (!Array.isArray(entries)) {
      return res.sendStatus(400);
    }

    const messages = new Map();
    const isId = (value) =>
      typeof value === "string" && /^\d+$/.test(value);

    for (const entry of entries) {
      if (!Array.isArray(entry?.messaging)) continue;

      for (const event of entry.messaging) {
        const message = event?.message;
        const accountId = event?.recipient?.id;
        const senderId = event?.sender?.id;

        if (
          !message ||
          message.is_echo === true ||
          message.is_deleted === true ||
          !isId(accountId) ||
          !isId(senderId) ||
          accountId === senderId ||
          typeof message.mid !== "string" ||
          message.mid.length === 0 ||
          message.mid.length > 1000 ||
          typeof message.text !== "string" ||
          message.text.trim().length === 0 ||
          message.text.length > 20000
        ) {
          continue;
        }

        const id = crypto
          .createHash("sha256")
          .update(JSON.stringify([accountId, message.mid]))
          .digest("hex");

        messages.set(id, {
          instagramUserId: accountId,
          senderId,
          messageId: message.mid,
          text: message.text,
          timestamp: Number.isSafeInteger(event.timestamp)
            ? event.timestamp
            : null,
          state: "received",
          receivedAt: FieldValue.serverTimestamp(),
        });
      }
    }

    if (messages.size > 100) {
      return res.sendStatus(503);
    }

    try {
      for (const [id, message] of messages) {
        try {
          await inbox.doc(id).create(message);
        } catch (error) {
          if (
            error?.code !== 6 &&
            error?.code !== "already-exists"
          ) {
            throw error;
          }
        }
      }

      console.log(
        "Instagram webhook: received messages:",
        messages.size,
      );

      return res.sendStatus(200);
    } catch {
      console.error("Instagram webhook: storage failed");
      return res.sendStatus(503);
    }
  });
}