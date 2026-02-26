export interface NotificationsConfig {
  clientId: string;
  dUser: { upn: string; displayName?: string };
  targetUser: { userId?: string; upn: string; displayName?: string };
  tenantId: string;
  teams: { chatId?: string };
  channels: { primary: Channel; fallback: Channel };
  triggers: Record<string, boolean>;
  rateLimit: {
    enabled: boolean;
    cooldownSeconds: Record<string, number>;
  };
}

export type NotificationType = "needsInput" | "blocked" | "completed" | "progress";
export type Channel = "teams" | "email";

export interface MessageResult {
  id: string;
  timestamp: string;
  from: string;
  content: string;
}
