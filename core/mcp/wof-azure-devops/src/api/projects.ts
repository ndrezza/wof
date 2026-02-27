import { coreApi } from "../client.js";
import type {
  AdoProject,
  AdoTeam,
  AdoProcess,
  AdoWorkItemType,
  AdoCollectionResponse,
} from "../types.js";

export async function listProjects(
  org: string,
  options?: {
    top?: number;
    skip?: number;
    stateFilter?: number;
    continuationToken?: number;
  }
): Promise<AdoCollectionResponse<AdoProject>> {
  return coreApi<AdoCollectionResponse<AdoProject>>(org, "_apis/projects", {
    params: {
      $top: options?.top,
      $skip: options?.skip,
      stateFilter: options?.stateFilter,
      continuationToken: options?.continuationToken,
    },
  });
}

export async function getProject(
  org: string,
  projectId: string
): Promise<AdoProject> {
  return coreApi<AdoProject>(org, `_apis/projects/${encodeURIComponent(projectId)}`);
}

export async function getProjectDetails(
  org: string,
  projectId: string,
  options?: {
    includeProcess?: boolean;
    includeTeams?: boolean;
    includeWorkItemTypes?: boolean;
    includeFields?: boolean;
    expandTeamIdentity?: boolean;
  }
): Promise<{
  project: AdoProject;
  process?: AdoProcess;
  teams?: AdoTeam[];
  workItemTypes?: AdoWorkItemType[];
}> {
  // Get project with capabilities
  const project = await coreApi<AdoProject>(
    org,
    `_apis/projects/${encodeURIComponent(projectId)}`,
    { params: { includeCapabilities: true } }
  );

  const result: {
    project: AdoProject;
    process?: AdoProcess;
    teams?: AdoTeam[];
    workItemTypes?: AdoWorkItemType[];
  } = { project };

  // Get process info if requested
  if (options?.includeProcess) {
    try {
      const processes = await coreApi<AdoCollectionResponse<AdoProcess>>(
        org,
        `_apis/process/processes`,
        { apiVersion: "7.1-preview.1" }
      );
      // Try to match from project capabilities
      const caps = (project as unknown as Record<string, unknown>).capabilities as
        | Record<string, Record<string, string>>
        | undefined;
      const processTemplateId = caps?.processTemplate?.templateTypeId;
      if (processTemplateId) {
        result.process = processes.value.find((p) => p.id === processTemplateId);
      }
    } catch {
      // Process info is optional
    }
  }

  // Get teams if requested
  if (options?.includeTeams) {
    try {
      const teams = await coreApi<AdoCollectionResponse<AdoTeam>>(
        org,
        `_apis/projects/${encodeURIComponent(projectId)}/teams`,
        {
          params: {
            $expandIdentity: options?.expandTeamIdentity,
          },
          apiVersion: "7.1-preview.3",
        }
      );
      result.teams = teams.value;
    } catch {
      // Teams info is optional
    }
  }

  // Get work item types if requested
  if (options?.includeWorkItemTypes) {
    try {
      const types = await coreApi<AdoCollectionResponse<AdoWorkItemType>>(
        org,
        `${encodeURIComponent(projectId)}/_apis/wit/workitemtypes`
      );
      if (options?.includeFields) {
        // Types already include fields in the response
        result.workItemTypes = types.value;
      } else {
        // Strip fields to reduce payload
        result.workItemTypes = types.value.map((t) => ({
          name: t.name,
          description: t.description,
          states: t.states,
        }));
      }
    } catch {
      // WIT info is optional
    }
  }

  return result;
}
