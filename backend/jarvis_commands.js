// Only the current user message can authorize an action.
// Model arguments, history and catalogue text cannot grant permission.

export function commandIntent(value) {
  const text = String(value || "")
    .normalize("NFKC")
    .toLowerCase()
    .trim();

  const quotedOrExplanation =
    /["“”`]|\b(translate|say|explain|tarjima|tushuntir|misol|nima|degani|example)\b|переведи|объясни|çevir/u;

  const question =
    /[?？]|\b(how|can you|could you|what if|example|misol|qanday|kanday|mumkinmi|мүмкүнбү|как|можешь|nasıl|mısın|misin)\b/u;

  if (
    !text ||
    text.length > 6000 ||
    quotedOrExplanation.test(text) ||
    question.test(text)
  ) {
    return "draft";
  }

  const cancelled =
    /\b(don't|do not|not now|never|stop|cancel|no)\b|yaratma|joylama|yuborma|qilma|килма|жаратпа|жарыялаба|не\s+(созда|публик|отвеч)|oluşturma\b|yayınlama\b|iptal/u;

  if (cancelled.test(text)) {
    return "draft";
  }

  const video =
    /video|vid[еe3]o|видео|ролик|reel|multfilm|multik|мультфильм|мультик|cartoon|çizgi\s+film/u.test(text);

  const make =
    /(?:^|\s)(?:create|generate|make|yarat|yaratib|yarating|yaratgin|tayyorla|tayyorlab|tayyorlang|tayyorlangiz|тайёрла|тайёрлаб|ярат|яратиб|жарат|жаратып|жаратыңыз|түзүп|түз|создай|создайте|сделай|oluştur|hazırla)(?:\s|[.,!]|$)/u.test(
      text,
    );

  const publish =
    /(?:^|\s)(?:publish|post|upload|joyla|joylab|joylang|joylashtir|joylashtirib|joylashtiring|yukla|yuklab|yuklang|yuklangiz|юклаб|юкла|жойла|жарыяла|жарыялап|жарыялаңыз|опубликуй|выложи|yayınla|paylaş)(?:\s|[.,!]|$)/u.test(
      text,
    );

  const instagram =
    /instagram|инстаграм/u.test(text);

  if (video && make) {
    return publish && instagram
      ? "create_publish"
      : "create";
  }

  // Ongoing customer replies require a separate explicit command.
  const customerReplies =
    /direct|direkt|директ|customer|mijoz|мижоз|кардар|клиент|müşteri|auto.?reply|авто.?ответ/u.test(
      text,
    );

  if (customerReplies && instagram) {
    const disable =
      /\b(disable|turn off)\b|o.?chir|очир|өчүр|выключи|отключи|kapat/u.test(
        text,
      );

    if (disable) {
      return "business_off";
    }

    const enable =
      /\b(enable|turn on|reply|answer)\b|javob ber|жавоб бер|жооп бер|включи|отвечай|yanıtla|cevap ver|etkinleştir/u.test(
        text,
      );

    if (enable) {
      return "business_on";
    }
  }

  return "draft";
}

export const automationTool = {
  name: "execute_video_command",
  description:
    "Submit one video task ONLY for an explicit current user " +
    "command to create a video. The server independently checks " +
    "the command. Includes title, an English visual prompt for " +
    "one 8-second scene, and caption with hashtags. Preserve the " +
    "requested spoken dialogue language. For ideas alone use " +
    "prepare_video_draft.",
  parameters: {
    type: "OBJECT",
    properties: {
      title: {
        type: "STRING",
      },
      prompt: {
        type: "STRING",
      },
      caption: {
        type: "STRING",
      },
    },
    required: [
      "title",
      "prompt",
      "caption",
    ],
  },
};

export function validDraft(args) {
  return (
    args &&
    typeof args.title === "string" &&
    args.title.trim() &&
    args.title.length <= 160 &&
    typeof args.prompt === "string" &&
    args.prompt.trim() &&
    args.prompt.length <= 2000 &&
    typeof args.caption === "string" &&
    args.caption.length <= 2200
  );
}