import { projectApi } from "../client.js";
export async function listPipelines(org, project, options) {
    const resp = await projectApi(org, project, "_apis/pipelines", {
        params: {
            $top: options?.top,
            orderBy: options?.orderBy,
        },
    });
    return resp.value;
}
export async function getPipeline(org, project, pipelineId, pipelineVersion) {
    return projectApi(org, project, `_apis/pipelines/${pipelineId}`, {
        params: {
            pipelineVersion: pipelineVersion,
        },
    });
}
export async function listPipelineRuns(org, project, pipelineId, options) {
    // Use the Builds API which supports richer filtering
    const resp = await projectApi(org, project, "_apis/build/builds", {
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
    });
    return resp.value;
}
export async function getPipelineRun(org, project, runId, pipelineId) {
    const run = await projectApi(org, project, `_apis/build/builds/${runId}`);
    if (pipelineId && run.pipeline?.id !== pipelineId) {
        throw new Error(`Run ${runId} belongs to pipeline ${run.pipeline?.id}, not ${pipelineId}`);
    }
    return run;
}
export async function downloadPipelineArtifact(org, project, runId, artifactPath, pipelineId) {
    if (pipelineId) {
        await getPipelineRun(org, project, runId, pipelineId);
    }
    // Parse artifact name and file path
    const slashIndex = artifactPath.indexOf("/");
    if (slashIndex < 0) {
        throw new Error("artifactPath must be in format: <artifactName>/<path/to/file>");
    }
    const artifactName = artifactPath.substring(0, slashIndex);
    const filePath = artifactPath.substring(slashIndex + 1);
    // Get artifact metadata
    const artifact = await projectApi(org, project, `_apis/build/builds/${runId}/artifacts`, {
        params: { artifactName },
    });
    // Download the specific file from the artifact
    const content = await projectApi(org, project, `_apis/build/builds/${runId}/artifacts`, {
        params: {
            artifactName,
            fileId: filePath,
            fileName: filePath,
        },
    });
    return typeof content === "string" ? content : JSON.stringify(content);
}
export async function getPipelineTimeline(org, project, runId) {
    const resp = await projectApi(org, project, `_apis/build/builds/${runId}/timeline`);
    return resp.records || [];
}
export async function getPipelineLog(org, project, runId, logId) {
    const resp = await projectApi(org, project, `_apis/build/builds/${runId}/logs/${logId}`);
    return resp.value ? resp.value.join("\n") : "";
}
export async function triggerPipeline(org, project, pipelineId, options) {
    const body = {};
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
    return projectApi(org, project, `_apis/pipelines/${pipelineId}/runs`, {
        method: "POST",
        body,
    });
}
