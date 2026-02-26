import type { NotificationType, MessageResult } from "./types.js";

const GRAPH_BASE = "https://graph.microsoft.com/v1.0";

const BADGE_COLORS: Record<string, string> = {
  needsInput: "#FF8C00",
  blocked: "#DC143C",
  completed: "#228B22",
  progress: "#4169E1",
};

const BADGE_LABELS: Record<string, string> = {
  needsInput: "INPUT NEEDED",
  blocked: "BLOCKED",
  completed: "COMPLETED",
  progress: "PROGRESS",
};

async function graphFetch(
  accessToken: string,
  url: string,
  options: RequestInit = {}
): Promise<Response> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${accessToken}`,
    "Content-Type": "application/json",
    ...(options.headers as Record<string, string> || {}),
  };
  return fetch(url, { ...options, headers });
}

export async function sendTeamsMessage(
  accessToken: string,
  chatId: string,
  message: string,
  type?: NotificationType
): Promise<{ success: boolean; error?: string }> {
  let htmlContent = message;

  if (type && BADGE_COLORS[type]) {
    const badge = `<span style='background-color:${BADGE_COLORS[type]};color:white;padding:2px 6px;border-radius:3px;font-size:11px;font-weight:bold'>${BADGE_LABELS[type]}</span>`;
    htmlContent = `${badge}<br/>${message}`;
  }

  const body = JSON.stringify({
    body: { contentType: "html", content: htmlContent },
  });

  const res = await graphFetch(accessToken, `${GRAPH_BASE}/chats/${chatId}/messages`, {
    method: "POST",
    body,
  });

  if (!res.ok) {
    const err = await res.text();
    return { success: false, error: `Teams send failed (${res.status}): ${err}` };
  }
  return { success: true };
}

export async function sendEmail(
  accessToken: string,
  recipientUpn: string,
  subject: string,
  message: string,
  senderUpn: string
): Promise<{ success: boolean; error?: string }> {
  const emailHtml = `<p>${message}</p><hr/><p style='font-size:11px;color:#888'>Sent by WOF Notification System from ${senderUpn}</p>`;

  const body = JSON.stringify({
    message: {
      subject,
      body: { contentType: "HTML", content: emailHtml },
      toRecipients: [{ emailAddress: { address: recipientUpn } }],
    },
    saveToSentItems: false,
  });

  const res = await graphFetch(accessToken, `${GRAPH_BASE}/me/sendMail`, {
    method: "POST",
    body,
  });

  if (!res.ok) {
    const err = await res.text();
    return { success: false, error: `Email send failed (${res.status}): ${err}` };
  }
  return { success: true };
}

export async function readMessages(
  accessToken: string,
  chatId: string,
  targetUserId: string,
  since?: string,
  maxMessages: number = 10
): Promise<MessageResult[]> {
  const top = maxMessages + 10; // Fetch extra for filtering
  const url = `${GRAPH_BASE}/chats/${chatId}/messages?$top=${top}&$orderby=createdDateTime desc`;

  const res = await graphFetch(accessToken, url, { method: "GET" });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Failed to fetch messages (${res.status}): ${err}`);
  }

  const data = (await res.json()) as {
    value: Array<{
      id: string;
      messageType: string;
      createdDateTime: string;
      from?: { user?: { id: string; displayName: string } };
      body: { contentType: string; content: string };
    }>;
  };

  if (!data.value) return [];

  const sinceDate = since ? new Date(since) : new Date(Date.now() - 3600000); // Default: last hour
  const results: MessageResult[] = [];

  for (const msg of data.value) {
    if (msg.messageType !== "message") continue;
    if (!msg.from?.user || msg.from.user.id !== targetUserId) continue;

    const msgDate = new Date(msg.createdDateTime);
    if (msgDate <= sinceDate) continue;

    let content = msg.body.content;
    if (msg.body.contentType === "html") {
      content = content
        .replace(/<[^>]+>/g, "")
        .replace(/&nbsp;/g, " ")
        .replace(/&amp;/g, "&")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .trim();
    }

    results.push({
      id: msg.id,
      timestamp: msg.createdDateTime,
      from: msg.from.user.displayName,
      content,
    });

    if (results.length >= maxMessages) break;
  }

  // Sort oldest first
  results.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());
  return results;
}
