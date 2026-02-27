import { projectApi } from "../client.js";
import type {
  AdoPipeline,
  AdoPipelineRun,
  AdoTimelineRecord,
  AdoBuildLog,
  AdoCollectionResponse,
} from "../types.js";

export async function listPipelines(
  org: string,
  project: string,
  options?: {
    top?: number;
    orderBy?: string;
  }
): Promise<AdoPipeline[]> {
  const resp = await projectApi<AdoCollectionResponse<AdoPipeline>>(
    org,
    project,
    "_apis/pipelines",
    {
      params: {
        $top: options?.top,
        orderBy: options?.orderBy,
      },
    }
  );
  return resp.value;
}

export async function getPipeline(
  org: string,
  project: string,
  pipelineId: number,
  pipelineVersion?: number
): Promise<AdoPipeline> {
  return projectApi<AdoPipeline>(
    org,
    project,
    `_apis/pipelines/${pipelineId}`,
    {
      params: {
        pipelineVersion: pipelineVersion,
      },
    }
  );
}

export async function listPipelineRuns(
  org: string,
  project: string,
  pipelineId: number,
  options?: {
    top?: number;
    branch?: string;
    state?: string;
    result?: string;
    createdFrom?: string;
    createdTo?: string;
    orderBy?: string;
    continuationToken?: string;
  }
): Promise<AdoPipelineRun[]> {
  // Use the Builds API which supports richer filtering
  const resp = await projectApi<AdoCollectionResponse<AdoPipelineRun>>(
    org,
    project,
    "_apis/build/builds",
    {
      params: {
        definitions: String(pipelineId),
        $top: options?.top || 50,
        branchName: options?.branch
          ? options.branch.startsWith("refs/")
            ? options.branch
            : `refs/heads/${options.branch}`
          : undefined,
        statusFilter: options?.state,
        resultFilter: options?.result,
        minTime: options?.createdFrom,
        maxTime: options?.createdTo,
        queryOrder: options?.orderBy === "createdDate asc"
          ? "startTimeAscending"
          : "startTimeDescending",
        continuationToken: options?.continuationToken,
      },
    }
  );
  return resp.value;
}

export async function getPipelineRun(
  org: string,
  project: string,
  runId: number,
  pipelineId?: number
): Promise<AdoPipelineRun> {
  const run = await projectApi<AdoPipelineRun>(
    org,
    project,
    `_apis/build/builds/${runId}`
  );

  if (pipelineId && run.pipeline?.id !== pipelineId) {
    throw new Error(
      `Run ${runId} belongs to pipeline ${run.pipeline?.id}, not ${pipelineId}`
    );
  }

  return run;
}

export async function downloadPipelineArtifact(
  org: string,
  project: string,
  runId: number,
  artifactPath: string,
  pipelineId?: number
): Promise<string> {
  if (pipelineId) {
    await getPipelineRun(org, project, runId, pipelineId);
  }

  // Parse artifact name and file path
  const slashIndex = artifactPath.indexOf("/");
  if (slashIndex < 0) {
    throw new Error(
      "artifactPath must be in format: <artifactName>/<path/to/file>"
    );
  }
  const artifactName = artifactPath.substring(0, slashIndex);
  const filePath = artifactPath.substring(slashIndex + 1);

  // Get artifact metadata
  const artifact = await projectApi<{
    id: number;
    name: string;
    resource: { type: string; url: string; downloadUrl: string };
  }>(
    org,
    project,
    `_apis/build/builds/${runId}/artifacts`,
    {
      params: { artifactName },
    }
  );

  // Download the specific file from the artifact
  const content = await projectApi<string>(
    org,
    project,
    `_apis/build/builds/${runId}/artifacts`,
    {
      params: {
        artifactName,
        fileId: filePath,
        fileName: filePath,
      },
    }
  );

  return typeof content === "string" ? content : JSON.stringify(content);
}

export async function getPipelineTimeline(
  org: string,
  project: string,
  runId: number
): Promise<AdoTimelineRecord[]> {
  const resp = await projectApi<{ records: AdoTimelineRecord[] }>(
    org,
    project,
    `_apis/build/builds/${runId}/timeline`
  );
  return resp.records || [];
}

export async function getPipelineLog(
  org: string,
  project: string,
  runId: number,
  logId: number
): Promise<string> {
  const resp = await projectApi<{ value: string[] }>(
    org,
    project,
    `_apis/build/builds/${runId}/logs/${logId}`
  );
  return resp.value ? resp.value.join("\n") : "";
}

export async function triggerPipeline(
  org: string,
  project: string,
  pipelineId: number,
  options?: {
    branch?: string;
    variables?: Record<string, { value: string; isSecret?: boolean }>;
    templateParameters?: Record<string, string>;
    stagesToSkip?: string[];
  }
): Promise<AdoPipelineRun> {
  const body: Record<string, unknown> = {};

  if (options?.branch) {
    body.resources = {
      repositories: {
        self: {
          refName: options.branch.startsWith("refs/")
            ? options.branch
            : `refs/heads/${options.branch}`,
        },
      },
    };
  }

  if (options?.variables) {
    body.variables = options.variables;
  }

  if (options?.templateParameters) {
    body.templateParameters = options.templateParameters;
  }

  if (options?.stagesToSkip?.length) {
    body.stagesToSkip = options.stagesToSkip;
  }

  return projectApi<AdoPipelineRun>(
    org,
    project,
    `_apis/pipelines/${pipelineId}/runs`,
    {
      method: "POST",
      body,
    }
  );
}
