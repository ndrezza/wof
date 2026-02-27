import { readFileSync } from "fs";
import { resolve, join } from "path";
let cachedConfig = null;
export function loadConfig() {
    if (cachedConfig)
        return cachedConfig;
    // Try env vars first
    const org = process.env.AZURE_DEVOPS_ORG;
    const pat = process.env.AZURE_DEVOPS_PAT;
    if (org && pat) {
        cachedConfig = {
            organization: org,
            pat,
            defaultProject: process.env.AZURE_DEVOPS_DEFAULT_PROJECT || undefined,
        };
        return cachedConfig;
    }
    // Fall back to config file
    const configPath = process.env.WOF_ADO_CONFIG
        ? resolve(process.env.WOF_ADO_CONFIG)
        : resolve(join(process.cwd(), ".ai", "config", "azure-devops.json"));
    try {
        const raw = readFileSync(configPath, "utf-8");
        const file = JSON.parse(raw);
        if (!file.organization || !file.pat) {
            throw new Error(`Missing required fields in ${configPath}: organization, pat`);
        }
        cachedConfig = {
            organization: file.organization,
            pat: file.pat,
            defaultProject: file.defaultProject,
        };
        return cachedConfig;
    }
    catch (err) {
        if (org || pat) {
            throw new Error("Incomplete env config: both AZURE_DEVOPS_ORG and AZURE_DEVOPS_PAT are required");
        }
        throw new Error(`Azure DevOps configuration not found. Set AZURE_DEVOPS_ORG + AZURE_DEVOPS_PAT env vars, ` +
            `or create ${configPath}. Error: ${err instanceof Error ? err.message : err}`);
    }
}
export function resolveOrg(organizationId) {
    const config = loadConfig();
    return organizationId || config.organization;
}
export function resolveProject(projectId) {
    const config = loadConfig();
    return projectId || config.defaultProject;
}
export function requireProject(projectId) {
    const resolved = resolveProject(projectId);
    if (!resolved) {
        throw new Error("Project ID is required. Either pass projectId or set AZURE_DEVOPS_DEFAULT_PROJECT.");
    }
    return resolved;
}
