import { loadConfig } from "./config.js";
import {
  ADO_CORE_HOST,
  ADO_VSSPS_HOST,
  ADO_VSSPS_APP_HOST,
  ADO_SEARCH_HOST,
} from "./types.js";

type HttpMethod = "GET" | "POST" | "PATCH" | "PUT" | "DELETE";

interface RequestOptions {
  method?: HttpMethod;
  body?: unknown;
  params?: Record<string, string | number | boolean | undefined>;
  contentType?: string;
  apiVersion?: string;
}

function buildAuthHeader(): string {
  const config = loadConfig();
  const encoded = Buffer.from(`:${config.pat}`).toString("base64");
  return `Basic ${encoded}`;
}

function buildUrl(
  baseUrl: string,
  path: string,
  params?: Record<string, string | number | boolean | undefined>,
  apiVersion?: string
): string {
  const url = new URL(path, baseUrl);
  const version = apiVersion || "7.1";
  url.searchParams.set("api-version", version);
  if (params) {
    for (const [key, value] of Object.entries(params)) {
      if (value !== undefined && value !== null) {
        url.searchParams.set(key, String(value));
      }
    }
  }
  return url.toString();
}

async function request<T>(url: string, options: RequestOptions = {}): Promise<T> {
  const { method = "GET", body, contentType } = options;

  const headers: Record<string, string> = {
    Authorization: buildAuthHeader(),
    Accept: "application/json",
  };

  if (body !== undefined) {
    headers["Content-Type"] = contentType || "application/json";
  }

  const response = await fetch(url, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });

  if (!response.ok) {
    const text = await response.text().catch(() => "");
    throw new Error(
      `ADO API ${method} ${url} returned ${response.status}: ${text}`
    );
  }

  const contentTypeHeader = response.headers.get("content-type") || "";
  if (contentTypeHeader.includes("application/json")) {
    return (await response.json()) as T;
  }

  // For non-JSON responses (file content, logs), return as text
  return (await response.text()) as unknown as T;
}

// Core API: https://dev.azure.com/{org}/_apis/...
// or: https://dev.azure.com/{org}/{project}/_apis/...
export function coreApi<T>(
  org: string,
  path: string,
  options?: RequestOptions
): Promise<T> {
  const base = `https://${ADO_CORE_HOST}/${org}/`;
  const url = buildUrl(base, path, options?.params, options?.apiVersion);
  return request<T>(url, options);
}

export function projectApi<T>(
  org: string,
  project: string,
  path: string,
  options?: RequestOptions
): Promise<T> {
  const base = `https://${ADO_CORE_HOST}/${org}/${encodeURIComponent(project)}/`;
  const url = buildUrl(base, path, options?.params, options?.apiVersion);
  return request<T>(url, options);
}

// VSSPS API: https://vssps.dev.azure.com/{org}/_apis/...
export function vsspsApi<T>(
  org: string,
  path: string,
  options?: RequestOptions
): Promise<T> {
  const base = `https://${ADO_VSSPS_HOST}/${org}/`;
  const url = buildUrl(base, path, options?.params, options?.apiVersion);
  return request<T>(url, options);
}

// App VSSPS API: https://app.vssps.visualstudio.com/_apis/...
export function vsspsAppApi<T>(
  path: string,
  options?: RequestOptions
): Promise<T> {
  const base = `https://${ADO_VSSPS_APP_HOST}/`;
  const url = buildUrl(base, path, options?.params, options?.apiVersion);
  return request<T>(url, options);
}

// Search API: https://almsearch.dev.azure.com/{org}/{project}/_apis/search/...
export function searchApi<T>(
  org: string,
  project: string,
  path: string,
  options?: RequestOptions
): Promise<T> {
  const base = `https://${ADO_SEARCH_HOST}/${org}/${encodeURIComponent(project)}/`;
  const url = buildUrl(base, path, options?.params, options?.apiVersion);
  return request<T>(url, options);
}

// Search API without project scope
export function searchOrgApi<T>(
  org: string,
  path: string,
  options?: RequestOptions
): Promise<T> {
  const base = `https://${ADO_SEARCH_HOST}/${org}/`;
  const url = buildUrl(base, path, options?.params, options?.apiVersion);
  return request<T>(url, options);
}
