import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import * as api from "../api/pipelines.js";
import { resolveOrg, requireProject } from "../config.js";

export function registerPipelineTools(server: McpServer) {
  server.tool(
    "list_pipelines",
    "List pipelines in a project",
    {
      projectId: z.string().optional().describe("The ID or name of the project"),
      top: z.number().optional().describe("Maximum number of pipelines to return"),
      orderBy: z.string().optional().describe("Order by field and direction"),
    },
    async ({ projectId, top, orderBy }) => {
      try {
        const org = resolveOrg();
        const proj = requireProject(projectId);
        const pipelines = await api.listPipelines(org, proj, { top, orderBy });
        return {
          content: [{ type: "text" as const, text: JSON.stringify(pipelines, null, 2) }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get_pipeline",
    "Get details of a specific pipeline",
    {
      projectId: z.string().optional().describe("The ID or name of the project"),
      pipelineId: z.number().describe("The numeric ID of the pipeline"),
      pipelineVersion: z.number().optional().describe("The version of the pipeline (latest if not specified)"),
    },
    async ({ projectId, pipelineId, pipelineVersion }) => {
      try {
        const org = resolveOrg();
        const proj = requireProject(projectId);
        const pipeline = await api.getPipeline(org, proj, pipelineId, pipelineVersion);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(pipeline, null, 2) }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "list_pipeline_runs",
    "List recent runs for a pipeline",
    {
      projectId: z.string().optional().describe("The ID or name of the project"),
      pipelineId: z.number().describe("Pipeline numeric ID"),
      top: z.number().min(1).max(100).default(50).optional().describe("Maximum number of runs to return (1-100)"),
      branch: z.string().optional().describe("Branch to filter by"),
      state: z.enum(["notStarted", "inProgress", "completed", "cancelling", "postponed"]).optional().describe("Filter by run state"),
      result: z.enum(["succeeded", "partiallySucceeded", "failed", "canceled", "none"]).optional().describe("Filter by final result"),
      createdFrom: z.string().optional().describe("Filter runs created at or after this time (ISO 8601)"),
      createdTo: z.string().optional().describe("Filter runs created at or before this time (ISO 8601)"),
      orderBy: z.enum(["createdDate desc", "createdDate asc"]).default("createdDate desc").optional().describe("Sort order"),
      continuationToken: z.string().optional().describe("Continuation token for pagination"),
    },
    async ({ projectId, pipelineId, top, branch, state, result, createdFrom, createdTo, orderBy, continuationToken }) => {
      try {
        const org = resolveOrg();
        const proj = requireProject(projectId);
        const runs = await api.listPipelineRuns(org, proj, pipelineId, {
          top,
          branch,
          state,
          result,
          createdFrom,
          createdTo,
          orderBy,
          continuationToken,
        });
        return {
          content: [{ type: "text" as const, text: JSON.stringify(runs, null, 2) }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get_pipeline_run",
    "Get details for a specific pipeline run",
    {
      projectId: z.string().optional().describe("The ID or name of the project"),
      runId: z.number().describe("Pipeline run identifier"),
      pipelineId: z.number().optional().describe("Optional guard; validates the run belongs to this pipeline"),
    },
    async ({ projectId, runId, pipelineId }) => {
      try {
        const org = resolveOrg();
        const proj = requireProject(projectId);
        const run = await api.getPipelineRun(org, proj, runId, pipelineId);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(run, null, 2) }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "download_pipeline_artifact",
    "Download a file from a pipeline run artifact and return its textual content",
    {
      projectId: z.string().optional().describe("The ID or name of the project"),
      runId: z.number().describe("Pipeline run identifier"),
      artifactPath: z.string().describe("Path to the file (format: <artifactName>/<path/to/file>)"),
      pipelineId: z.number().optional().describe("Optional guard; validates the run belongs to this pipeline"),
    },
    async ({ projectId, runId, artifactPath, pipelineId }) => {
      try {
        const org = resolveOrg();
        const proj = requireProject(projectId);
        const content = await api.downloadPipelineArtifact(org, proj, runId, artifactPath, pipelineId);
        return {
          content: [{ type: "text" as const, text: content }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "pipeline_timeline",
    "Get the timeline (stages, jobs, tasks) for a pipeline run",
    {
      projectId: z.string().optional().describe("The ID or name of the project"),
      runId: z.number().describe("Pipeline run identifier"),
    },
    async ({ projectId, runId }) => {
      try {
        const org = resolveOrg();
        const proj = requireProject(projectId);
        const records = await api.getPipelineTimeline(org, proj, runId);
        return {
          content: [{ type: "text" as const, text: JSON.stringify(records, null, 2) }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "get_pipeline_log",
    "Get the log content for a specific log in a pipeline run",
    {
      projectId: z.string().optional().describe("The ID or name of the project"),
      runId: z.number().describe("Pipeline run identifier"),
      logId: z.number().describe("The log ID (from pipeline_timeline records)"),
    },
    async ({ projectId, runId, logId }) => {
      try {
        const org = resolveOrg();
        const proj = requireProject(projectId);
        const logContent = await api.getPipelineLog(org, proj, runId, logId);
        return {
          content: [{ type: "text" as const, text: logContent }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );

  server.tool(
    "trigger_pipeline",
    "Trigger a pipeline run",
    {
      projectId: z.string().optional().describe("The ID or name of the project"),
      pipelineId: z.number().describe("The numeric ID of the pipeline to trigger"),
      branch: z.string().optional().describe("The branch to run the pipeline on"),
      variables: z.record(z.string(), z.object({
        value: z.string(),
        isSecret: z.boolean().optional(),
      })).optional().describe("Variables to pass to the pipeline run"),
      templateParameters: z.record(z.string(), z.string()).optional().describe("Parameters for template-based pipelines"),
      stagesToSkip: z.array(z.string()).optional().describe("Stages to skip in the pipeline run"),
    },
    async ({ projectId, pipelineId, branch, variables, templateParameters, stagesToSkip }) => {
      try {
        const org = resolveOrg();
        const proj = requireProject(projectId);
        const run = await api.triggerPipeline(org, proj, pipelineId, {
          branch,
          variables,
          templateParameters,
          stagesToSkip,
        });
        return {
          content: [{ type: "text" as const, text: JSON.stringify(run, null, 2) }],
        };
      } catch (err) {
        return {
          content: [{ type: "text" as const, text: `Error: ${err instanceof Error ? err.message : err}` }],
          isError: true,
        };
      }
    }
  );
}
