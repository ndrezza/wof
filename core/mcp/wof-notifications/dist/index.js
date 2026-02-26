import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { loadConfig } from "./config.js";
import { startAuthentication, waitForAuth, getAccessToken, isAuthenticated, isAuthInProgress } from "./auth.js";
import { sendTeamsMessage, sendEmail, readMessages } from "./graph-client.js";
import { RateLimiter } from "./rate-limiter.js";
const rateLimiter = new RateLimiter();
let lastReadTimestamp = null;
const server = new McpServer({
    name: "wof-notifications",
    version: "1.0.0",
});
// ============================================================================
// Tool: authenticate
// ============================================================================
server.tool("authenticate", "Authenticate the d-user with Microsoft Graph via device code flow. Required before sending or reading messages. Only needed once per server session.", {}, async () => {
    try {
        const config = loadConfig();
        if (isAuthenticated()) {
            return {
                content: [{
                        type: "text",
                        text: JSON.stringify({
                            status: "already_authenticated",
                            dUser: config.dUser.upn,
                            message: "Already authenticated. No action needed.",
                        }),
                    }],
            };
        }
        const startResult = await startAuthentication(config);
        if (startResult.alreadyAuthenticated) {
            return {
                content: [{
                        type: "text",
                        text: JSON.stringify({
                            status: "authenticated",
                            dUser: config.dUser.upn,
                            expiresOn: startResult.result.expiresOn?.toISOString(),
                            message: `Authenticated as ${config.dUser.upn}. Notifications are now operational.`,
                        }),
                    }],
            };
        }
        // Return device code info immediately — auth continues in background
        const dc = startResult.deviceCode;
        return {
            content: [{
                    type: "text",
                    text: JSON.stringify({
                        status: "device_code_pending",
                        verificationUri: dc.verificationUri,
                        userCode: dc.userCode,
                        message: dc.message,
                        expiresInSeconds: dc.expiresInSeconds,
                        instructions: "Open the URL in a browser and enter the code to sign in. Then call get_status to verify authentication completed.",
                    }),
                }],
        };
    }
    catch (err) {
        return {
            content: [{
                    type: "text",
                    text: JSON.stringify({
                        status: "error",
                        error: err instanceof Error ? err.message : String(err),
                    }),
                }],
            isError: true,
        };
    }
});
// ============================================================================
// Tool: send_notification
// ============================================================================
server.tool("send_notification", "Send a notification from the d-user to the target user via Teams chat or email.", {
    message: z.string().describe("The notification message text"),
    type: z
        .enum(["needsInput", "blocked", "completed", "progress"])
        .optional()
        .describe("Notification type (adds a colored badge). If the type is disabled in triggers config, the notification is silently skipped."),
    channel: z
        .enum(["teams", "email", "auto"])
        .default("auto")
        .describe("Delivery channel. 'auto' uses the primary channel from config, falls back if it fails."),
    subject: z
        .string()
        .default("WOF Notification")
        .describe("Email subject line (only used for email channel)"),
}, async ({ message, type, channel, subject }) => {
    try {
        const config = loadConfig();
        const accessToken = await getAccessToken(config);
        // Check trigger filter
        if (type && config.triggers[type] === false) {
            return {
                content: [{
                        type: "text",
                        text: JSON.stringify({
                            status: "filtered",
                            reason: `Trigger '${type}' is disabled in configuration.`,
                        }),
                    }],
            };
        }
        // Check rate limit
        if (config.rateLimit?.enabled) {
            const cooldownKey = type || "default";
            const cooldownSeconds = config.rateLimit.cooldownSeconds[cooldownKey] ??
                config.rateLimit.cooldownSeconds["default"] ??
                0;
            const check = rateLimiter.isAllowed(cooldownKey, cooldownSeconds);
            if (!check.allowed) {
                return {
                    content: [{
                            type: "text",
                            text: JSON.stringify({
                                status: "rate_limited",
                                type: cooldownKey,
                                remainingSeconds: check.remainingSeconds,
                                message: `Rate limited. Try again in ${check.remainingSeconds}s.`,
                            }),
                        }],
                };
            }
        }
        // Resolve channel
        let primaryChannel = channel === "auto" ? (config.channels?.primary || "teams") : channel;
        const fallbackChannel = config.channels?.fallback || "email";
        // Send
        let result = await trySendOnChannel(accessToken, config, primaryChannel, message, type, subject);
        if (!result.success && primaryChannel !== fallbackChannel) {
            result = await trySendOnChannel(accessToken, config, fallbackChannel, message, type, subject);
            if (result.success) {
                result.channel = fallbackChannel;
                result.fallback = true;
            }
        }
        if (result.success) {
            // Record rate limit
            const cooldownKey = type || "default";
            rateLimiter.record(cooldownKey);
        }
        return {
            content: [{
                    type: "text",
                    text: JSON.stringify(result),
                }],
            isError: !result.success,
        };
    }
    catch (err) {
        return {
            content: [{
                    type: "text",
                    text: JSON.stringify({
                        success: false,
                        error: err instanceof Error ? err.message : String(err),
                    }),
                }],
            isError: true,
        };
    }
});
async function trySendOnChannel(accessToken, config, channel, message, type, subject) {
    if (channel === "teams") {
        if (!config.teams?.chatId) {
            return { success: false, error: "No Teams chatId configured. Run graph-auth.ps1 first." };
        }
        const res = await sendTeamsMessage(accessToken, config.teams.chatId, message, type);
        return { ...res, channel: "teams" };
    }
    else {
        if (!config.targetUser?.upn) {
            return { success: false, error: "No target user UPN configured." };
        }
        const res = await sendEmail(accessToken, config.targetUser.upn, subject || "WOF Notification", message, config.dUser.upn);
        return { ...res, channel: "email" };
    }
}
// ============================================================================
// Tool: read_messages
// ============================================================================
server.tool("read_messages", "Read new messages from the target user in the Teams chat. Returns messages sent since the last read (or last hour on first call).", {
    since: z
        .string()
        .optional()
        .describe("ISO 8601 timestamp. Only return messages after this time. Defaults to last read position or last hour."),
    maxMessages: z.number().default(10).describe("Maximum number of messages to return"),
    markAsRead: z
        .boolean()
        .default(true)
        .describe("Update the read position after fetching messages"),
}, async ({ since, maxMessages, markAsRead }) => {
    try {
        const config = loadConfig();
        const accessToken = await getAccessToken(config);
        if (!config.teams?.chatId) {
            throw new Error("No Teams chatId configured. Run graph-auth.ps1 first.");
        }
        if (!config.targetUser?.userId) {
            throw new Error("No target user ID configured. Run graph-auth.ps1 first.");
        }
        const sinceTs = since || lastReadTimestamp || undefined;
        const messages = await readMessages(accessToken, config.teams.chatId, config.targetUser.userId, sinceTs, maxMessages);
        if (markAsRead && messages.length > 0) {
            lastReadTimestamp = messages[messages.length - 1].timestamp;
        }
        return {
            content: [{
                    type: "text",
                    text: JSON.stringify({
                        count: messages.length,
                        since: sinceTs || "(last hour)",
                        messages,
                    }),
                }],
        };
    }
    catch (err) {
        return {
            content: [{
                    type: "text",
                    text: JSON.stringify({
                        error: err instanceof Error ? err.message : String(err),
                    }),
                }],
            isError: true,
        };
    }
});
// ============================================================================
// Tool: get_status
// ============================================================================
server.tool("get_status", "Get the current status of the notification server: authentication state, configuration, and rate limit state.", {}, async () => {
    try {
        const config = loadConfig();
        // If auth is in progress, do a quick non-blocking check to see if it completed
        if (isAuthInProgress() && !isAuthenticated()) {
            // waitForAuth returns immediately if no pending auth, or awaits the pending promise
            // We use Promise.race with a short timeout so get_status doesn't block
            const quickCheck = await Promise.race([
                waitForAuth().then(() => true).catch(() => false),
                new Promise((resolve) => setTimeout(() => resolve(false), 500)),
            ]);
            // isAuthenticated() will now reflect the updated state if auth completed
            if (quickCheck) {
                process.stderr.write("[wof-notifications] Auth confirmed via get_status check.\n");
            }
        }
        return {
            content: [{
                    type: "text",
                    text: JSON.stringify({
                        authenticated: isAuthenticated(),
                        authInProgress: isAuthInProgress(),
                        dUser: config.dUser.upn,
                        targetUser: config.targetUser.upn,
                        chatId: config.teams?.chatId || null,
                        channels: config.channels,
                        triggers: config.triggers,
                        rateLimit: config.rateLimit?.enabled
                            ? { enabled: true, state: rateLimiter.getState() }
                            : { enabled: false },
                        lastReadTimestamp,
                    }),
                }],
        };
    }
    catch (err) {
        return {
            content: [{
                    type: "text",
                    text: JSON.stringify({
                        error: err instanceof Error ? err.message : String(err),
                    }),
                }],
            isError: true,
        };
    }
});
// ============================================================================
// Start server
// ============================================================================
async function main() {
    // Validate config on startup
    try {
        const config = loadConfig();
        process.stderr.write(`[wof-notifications] Config loaded: ${config.dUser.upn} -> ${config.targetUser.upn}\n`);
    }
    catch (err) {
        process.stderr.write(`[wof-notifications] WARNING: Config error: ${err instanceof Error ? err.message : err}\n` +
            `[wof-notifications] The 'authenticate' tool will fail until config is fixed.\n`);
    }
    const transport = new StdioServerTransport();
    await server.connect(transport);
    process.stderr.write("[wof-notifications] MCP server started.\n");
}
main().catch((err) => {
    process.stderr.write(`[wof-notifications] Fatal: ${err}\n`);
    process.exit(1);
});
