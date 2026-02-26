import { readFileSync } from "fs";
import { resolve, join } from "path";
import type { NotificationsConfig } from "./types.js";

let cachedConfig: NotificationsConfig | null = null;
let configPath: string | null = null;

export function getConfigPath(): string {
  if (configPath) return configPath;

  const envPath = process.env.WOF_NOTIFICATIONS_CONFIG;
  if (envPath) {
    configPath = resolve(envPath);
  } else {
    configPath = resolve(join(process.cwd(), ".ai", "config", "notifications.json"));
  }
  return configPath;
}

export function loadConfig(): NotificationsConfig {
  if (cachedConfig) return cachedConfig;

  const path = getConfigPath();
  const raw = readFileSync(path, "utf-8");
  const config = JSON.parse(raw) as NotificationsConfig;

  // Validate required fields
  const missing: string[] = [];
  if (!config.clientId) missing.push("clientId");
  if (!config.tenantId) missing.push("tenantId");
  if (!config.dUser?.upn) missing.push("dUser.upn");
  if (!config.targetUser?.upn) missing.push("targetUser.upn");

  if (missing.length > 0) {
    throw new Error(
      `Missing required fields in notifications.json: ${missing.join(", ")}. Run graph-auth.ps1 or register-notification-app.ps1 first.`
    );
  }

  // Defaults
  if (!config.channels) {
    config.channels = { primary: "teams", fallback: "email" };
  }
  if (!config.triggers) {
    config.triggers = { needsInput: true, blocked: true, completed: true, progress: false };
  }
  if (!config.rateLimit) {
    config.rateLimit = { enabled: false, cooldownSeconds: {} };
  }

  cachedConfig = config;
  return config;
}
