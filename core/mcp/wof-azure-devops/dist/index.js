import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { loadConfig } from "./config.js";
import { registerIdentityTools } from "./tools/identity.js";
import { registerProjectTools } from "./tools/projects.js";
import { registerRepositoryTools } from "./tools/repositories.js";
import { registerGitTools } from "./tools/git.js";
import { registerWorkItemTools } from "./tools/work-items.js";
import { registerPullRequestTools } from "./tools/pull-requests.js";
import { registerPipelineTools } from "./tools/pipelines.js";
import { registerWikiTools } from "./tools/wiki.js";
import { registerSearchTools } from "./tools/search.js";
const server = new McpServer({
    name: "wof-azure-devops",
    version: "1.0.0",
});
// Register all tool groups
registerIdentityTools(server);
registerProjectTools(server);
registerRepositoryTools(server);
registerGitTools(server);
registerWorkItemTools(server);
registerPullRequestTools(server);
registerPipelineTools(server);
registerWikiTools(server);
registerSearchTools(server);
async function main() {
    // Validate config on startup
    try {
        const config = loadConfig();
        process.stderr.write(`[wof-azure-devops] Config loaded: org=${config.organization}` +
            (config.defaultProject ? `, project=${config.defaultProject}` : "") +
            "\n");
    }
    catch (err) {
        process.stderr.write(`[wof-azure-devops] WARNING: Config error: ${err instanceof Error ? err.message : err}\n` +
            `[wof-azure-devops] Tools will fail until config is provided.\n`);
    }
    const transport = new StdioServerTransport();
    await server.connect(transport);
    process.stderr.write("[wof-azure-devops] MCP server started (44 tools registered).\n");
}
main().catch((err) => {
    process.stderr.write(`[wof-azure-devops] Fatal: ${err}\n`);
    process.exit(1);
});
