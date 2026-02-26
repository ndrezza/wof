import {
  PublicClientApplication,
  type AccountInfo,
  type AuthenticationResult,
  type DeviceCodeRequest,
} from "@azure/msal-node";
import type { NotificationsConfig } from "./types.js";

const GRAPH_SCOPES = [
  "Chat.ReadWrite",
  "Mail.Send",
  "User.Read",
  "User.ReadBasic.All",
  "offline_access",
];

let msalApp: PublicClientApplication | null = null;
let cachedAccount: AccountInfo | null = null;
let authenticated = false;
let authInProgress = false;
let pendingAuth: Promise<AuthenticationResult> | null = null;
let lastDeviceCodeInfo: DeviceCodeInfo | null = null;

export interface DeviceCodeInfo {
  userCode: string;
  verificationUri: string;
  message: string;
  expiresInSeconds: number;
}

export type StartAuthResult =
  | { alreadyAuthenticated: true; result: AuthenticationResult }
  | { alreadyAuthenticated: false; deviceCode: DeviceCodeInfo };

export function isAuthenticated(): boolean {
  return authenticated;
}

export function isAuthInProgress(): boolean {
  return authInProgress;
}

function initMsalApp(config: NotificationsConfig): PublicClientApplication {
  if (!msalApp) {
    msalApp = new PublicClientApplication({
      auth: {
        clientId: config.clientId,
        authority: `https://login.microsoftonline.com/${config.tenantId}`,
      },
    });
  }
  return msalApp;
}

export async function getAccessToken(config: NotificationsConfig): Promise<string> {
  const app = initMsalApp(config);

  // Try silent with cached account
  if (cachedAccount) {
    try {
      const result = await app.acquireTokenSilent({
        scopes: GRAPH_SCOPES,
        account: cachedAccount,
      });
      if (result?.accessToken) {
        authenticated = true;
        return result.accessToken;
      }
    } catch {
      // Silent failed, will need re-auth
      cachedAccount = null;
      authenticated = false;
    }
  }

  // Try to find accounts in cache
  const accounts = await app.getTokenCache().getAllAccounts();
  if (accounts.length > 0) {
    cachedAccount = accounts[0];
    try {
      const result = await app.acquireTokenSilent({
        scopes: GRAPH_SCOPES,
        account: cachedAccount,
      });
      if (result?.accessToken) {
        authenticated = true;
        return result.accessToken;
      }
    } catch {
      cachedAccount = null;
    }
  }

  throw new Error(
    "Not authenticated. Use the 'authenticate' tool to start device code flow."
  );
}

/**
 * Start device code authentication flow.
 * Returns the device code info immediately so it can be shown to the user.
 * The auth flow continues in the background — cachedAccount and authenticated
 * are set when the user completes the flow.
 */
export async function startAuthentication(
  config: NotificationsConfig
): Promise<StartAuthResult> {
  // If auth is already in progress, return the existing device code info
  if (authInProgress && lastDeviceCodeInfo) {
    return { alreadyAuthenticated: false, deviceCode: lastDeviceCodeInfo };
  }

  if (authInProgress) {
    throw new Error(
      "Authentication already in progress but device code not yet available."
    );
  }

  const app = initMsalApp(config);

  // Try silent first
  const accounts = await app.getTokenCache().getAllAccounts();
  if (accounts.length > 0) {
    try {
      const result = await app.acquireTokenSilent({
        scopes: GRAPH_SCOPES,
        account: accounts[0],
      });
      if (result?.accessToken) {
        cachedAccount = accounts[0];
        authenticated = true;
        return { alreadyAuthenticated: true, result };
      }
    } catch {
      // Fall through to device code
    }
  }

  // Start device code flow — return the code immediately, auth continues in background
  authInProgress = true;
  lastDeviceCodeInfo = null;

  const deviceCodeInfo = await new Promise<DeviceCodeInfo>((resolve, reject) => {
    let callbackFired = false;

    const request: DeviceCodeRequest = {
      scopes: GRAPH_SCOPES,
      deviceCodeCallback: (response) => {
        callbackFired = true;
        resolve({
          userCode: response.userCode,
          verificationUri: response.verificationUri,
          message: response.message,
          expiresInSeconds: response.expiresIn,
        });
      },
    };

    // Start auth in background — don't await
    pendingAuth = app
      .acquireTokenByDeviceCode(request)
      .then((result) => {
        if (!result?.accessToken) {
          throw new Error("No access token received from device code flow.");
        }
        cachedAccount = result.account;
        authenticated = true;
        authInProgress = false;
        lastDeviceCodeInfo = null;
        process.stderr.write("[wof-notifications] Device code auth completed.\n");
        return result;
      })
      .catch((err) => {
        authInProgress = false;
        pendingAuth = null;
        lastDeviceCodeInfo = null;
        // If the callback never fired, reject the deviceCode promise
        if (!callbackFired) {
          reject(err);
        }
        throw err;
      });

    // Suppress unhandled rejection — pendingAuth will be consumed by getAccessToken or waitForAuth
    pendingAuth.catch(() => {});
  });

  lastDeviceCodeInfo = deviceCodeInfo;
  return { alreadyAuthenticated: false, deviceCode: deviceCodeInfo };
}

/**
 * Wait for a pending device code auth flow to complete.
 * Returns the result if successful, or null if no pending auth or if it failed.
 */
export async function waitForAuth(): Promise<AuthenticationResult | null> {
  if (!pendingAuth) return null;
  try {
    const result = await pendingAuth;
    pendingAuth = null;
    return result;
  } catch {
    pendingAuth = null;
    return null;
  }
}
