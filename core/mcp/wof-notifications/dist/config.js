import { readFileSync } from "fs";
import { resolve, join } from "path";
let cachedConfig = null;
let configPath = null;
export function getConfigPath() {
    if (configPath)
        return configPath;
    const envPath = process.env.WOF_NOTIFICATIONS_CONFIG;
    if (envPath) {
        configPath = resolve(envPath);
    }
    else {
        configPath = resolve(join(process.cwd(), ".ai", "config", "notifications.json"));
    }
    return configPath;
}
export function loadConfig() {
    if (cachedConfig)
        return cachedConfig;
    const path = getConfigPath();
    const raw = readFileSync(path, "utf-8");
    const config = JSON.parse(raw);
    // Validate required fields
    const missing = [];
    if (!config.clientId)
        missing.push("clientId");
    if (!config.tenantId)
        missing.push("tenantId");
    if (!config.dUser?.upn)
        missing.push("dUser.upn");
    if (!config.targetUser?.upn)
        missing.push("targetUser.upn");
    if (missing.length > 0) {
        throw new Error(`Missing required fields in notifications.json: ${missing.join(", ")}. Run graph-auth.ps1 or register-notification-app.ps1 first.`);
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
