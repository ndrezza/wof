# Research Report: Index Database Functionality for WOF

**Work Item:** #2971 - Add index database functionality to WOF
**Date:** 2026-02-22
**Status:** Research Complete

---

## 1. Executive Summary

**Key Finding:** Claude Code has **no native index database**. It relies entirely on on-the-fly file search (Glob, Grep) and manually curated context (CLAUDE.md, memory files). This is a deliberate design choice by Anthropic that trades indexing overhead for simplicity, but it creates limitations for large codebases where semantic search would significantly improve context retrieval.

**Recommended Approach:** A tiered strategy for WOF:

| Tier | Approach | Effort | Value |
|------|----------|--------|-------|
| **Tier 1** (Quick Win) | Adopt an existing MCP server (Claude Context or CocoIndex Code) as optional WOF extension | Days | Immediate semantic search for all WOI projects |
| **Tier 2** (WOF-Native) | Build a WOF index module with configurable backend (local sqlite-vec or Azure AI Search) | Weeks | Integrated `/wof index` commands, project-aware indexing |
| **Tier 3** (Enterprise) | ARM/Bicep templates for Azure AI Search + Azure OpenAI embeddings | Weeks | Enterprise-grade, shared team indexes, compliance-ready |

**Recommendation:** Start with **Tier 1** - integrate Claude Context MCP (5.4k GitHub stars, Milvus/Zilliz backend, hybrid BM25 + vector search) as an optional WOF extension configurable via `/wof configure`. This delivers immediate value while Tier 2/3 are evaluated.

---

## 2. Claude Code Native Capabilities

### What Claude Code Does Today

| Capability | Mechanism | Scope |
|------------|-----------|-------|
| **File search** | `Glob` tool (pattern matching) | File names and paths |
| **Content search** | `Grep` tool (ripgrep-based regex) | File contents, line-level |
| **Context loading** | `CLAUDE.md` files (auto-loaded) | Project instructions, conventions |
| **Memory** | `.claude/` memory directory | Persistent notes across sessions |
| **Sub-agents** | `Task` tool with specialized agents | Parallel exploration |
| **Auto-compaction** | Context window compression | Prevents context overflow |
| **MCP integration** | Model Context Protocol servers | Extensible tool access |

### Why Anthropic Chose This Approach

Anthropic's design philosophy for Claude Code prioritizes:

1. **Zero setup cost** - No indexing step, no database to maintain, works immediately on any codebase
2. **Always fresh** - Grep/Glob read live files, never stale indexes
3. **Simplicity** - No embedding model dependencies, no vector DB infrastructure
4. **Privacy** - No code leaves the machine for embedding generation (unless using cloud APIs)
5. **Extensibility** - MCP protocol allows users to add indexing if needed

### Limitations for Large Codebases

| Limitation | Impact | When It Matters |
|------------|--------|-----------------|
| **No semantic search** | Can't find code by concept ("authentication logic") | Unfamiliar codebases, cross-cutting concerns |
| **Linear search cost** | Grep scans all files every time | Repos with 10k+ files, monorepos |
| **No symbol awareness** | Can't navigate by function/class relationships | Refactoring, dependency analysis |
| **No cross-file linking** | Doesn't understand import graphs | Architecture exploration |
| **Context window pressure** | Must retrieve relevant code within token limits | Large files, many dependencies |
| **No persistence** | Search results don't carry across sessions | Repeated exploration of same areas |

For WOF projects specifically, this means the Orchestrator agent spends tokens on search that could be spent on reasoning, and Workers may miss relevant context when implementing cross-cutting changes.

---

## 3. Competitor Landscape

### How AI Coding Tools Handle Indexing

| Tool | Indexing Method | Embedding Model | Vector DB | Storage | Auto Index |
|------|----------------|-----------------|-----------|---------|------------|
| **Cursor** | Tree-sitter AST chunking | Custom / OpenAI | Turbopuffer (cloud) | Cloud (S3/GCS/Blob) | Yes (5-10 min) |
| **GitHub Copilot** | Remote semantic search + RAG | Proprietary | GitHub infrastructure | Cloud | Yes (on commit) |
| **Continue.dev** | Embeddings + ripgrep hybrid | Voyage-code-3 / Transformers.js | LanceDB (local) | Local only | Yes (continuous) |
| **Windsurf** | AST + embeddings + Riptide reasoning | Proprietary Riptide | Proprietary | Local + optional cloud | Yes |
| **RooCode** | Memory Bank (file-based) | N/A | N/A | Local markdown files | Hybrid (auto + manual) |
| **Claude Code** | Glob + Grep (no index) | N/A | N/A | N/A | N/A |

### Key Takeaways

1. **Tree-sitter is the de facto standard** for semantic code chunking - Cursor, Windsurf, Continue, and most MCP servers use it
2. **Hybrid search wins** - Combining vector similarity with keyword search (BM25) consistently outperforms either alone
3. **Local-first is trending** - Continue.dev (LanceDB), Windsurf, and RooCode all prioritize local storage for privacy
4. **Cloud scales better** - Cursor's Turbopuffer handles 100B+ vectors; local solutions struggle past 10M lines
5. **Automatic indexing is expected** - All competitors except RooCode index automatically in the background

### Detailed Notes

**Cursor** stands out for scale: tree-sitter AST chunking creates structurally coherent code chunks, embeddings are encrypted client-side, and Turbopuffer on object storage (S3) handles massive vector counts at 20x lower cost than traditional vector DBs. Privacy mode (used by 50% of users) ensures raw code is never stored server-side.

**Continue.dev** is the closest model to what WOF could build: fully open-source, local-first with LanceDB, supports swappable embedding models (Voyage-code-3 recommended), and handles 10M-line codebases creating ~1M vectors. Their architecture is well-documented and MIT-licensed.

**Windsurf's Riptide** engine demonstrates that adding a reasoning layer on top of embeddings (evaluating relevance, not just similarity) yields 200% improvement in retrieval recall. This is relevant for WOF's Validator/Critic roles.

**RooCode's Memory Bank** is file-based (markdown), not vector-based. It's closer to what WOF already does with `.ai/memory/` files. Effective for maintaining project context, but doesn't provide semantic code search.

---

## 4. Embedding Models Comparison

### Cloud Embedding Models

| Model | Provider | Dimensions | Price (per 1M tokens) | Code-Specific | Context Length |
|-------|----------|------------|----------------------|---------------|----------------|
| **voyage-code-3** | Voyage AI | 2048 (configurable: 256-2048) | ~$0.22 (AWS), free first 200M tokens | Yes - trained on code, +13.8% over OpenAI on code tasks | 32K tokens |
| **text-embedding-3-small** | OpenAI | 1536 (configurable) | $0.02 | No (general purpose) | 8K tokens |
| **text-embedding-3-large** | OpenAI | 3072 (configurable: 256-3072) | $0.13 | No (general purpose) | 8K tokens |
| **Azure OpenAI text-embedding-3-small** | Microsoft | 1536 | $0.02 | No (same as OpenAI) | 8K tokens |
| **Azure OpenAI text-embedding-3-large** | Microsoft | 3072 | $0.13 | No (same as OpenAI) | 8K tokens |

### Local Embedding Models

| Model | Dimensions | Size | Quality (MTEB) | Latency | Best For |
|-------|-----------|------|----------------|---------|----------|
| **all-MiniLM-L6-v2** | 384 | 22 MB (22.7M params) | 56% top-5 | <30ms | Real-time RAG, low resource |
| **nomic-embed-text** | 768 (configurable: 256-768) | 305M active params (MoE) | Higher than MiniLM | Moderate | Quality + multilingual |
| **CodeRankEmbed** (nomic-ai) | 768 | Code-specific | Code-optimized | ~50 emb/sec CPU | Code-specific local search |
| **Jina embeddings** | 1024 | Moderate | Good | Moderate | Symbol-aware search |

### Recommendation

For WOF's use case (code search in enterprise environments):

- **Best cloud option:** `voyage-code-3` - purpose-built for code, 13-16% better than OpenAI on code retrieval tasks, supports dimension reduction for cost optimization
- **Best budget cloud:** `text-embedding-3-small` at $0.02/M tokens - 6-7x cheaper than alternatives, adequate for most codebases
- **Best local option:** `all-MiniLM-L6-v2` - 22MB, sub-30ms latency, runs anywhere including CI/CD pipelines
- **Best local + quality:** `nomic-embed-text` via Ollama - good quality, multilingual, flexible dimensions

---

## 5. Azure-Native Options

For enterprise WOF deployments where infrastructure must be Azure-hosted.

### Azure AI Search

| Tier | Price/Month | Storage | Max Indexes | Vector Support | Best For |
|------|------------|---------|-------------|----------------|----------|
| **Free** | $0 | 50 MB | 3 | Yes | Development, POC |
| **Basic** | ~$74 | 15 GB (45 GB max) | 15 | Yes | Small teams, single project |
| **Standard S1** | ~$245 | 160 GB (1.9 TB max) | 50 | Yes | Production, multi-project |

**Key features:**
- Native vector search included at no extra cost (no per-query charge for vector queries)
- Hybrid search: vector + BM25 keyword search in a single query
- Semantic ranker available (usage-based pricing) for enhanced relevance
- Built-in AI enrichment pipeline (skillsets) for automatic chunking and embedding
- REST API compatible with any client
- Managed service with SLA

**Estimated monthly cost for WOF:**
- Small team (1-3 projects): Basic tier = **~$74/month** + embedding costs
- Enterprise (10+ projects): Standard S1 = **~$245/month** + embedding costs
- Embedding costs (Azure OpenAI): ~$0.02/M tokens with text-embedding-3-small

### Azure Cosmos DB (Vector Search)

| Feature | Details |
|---------|---------|
| **Vector support** | DiskANN-based vector indexing |
| **Pricing** | RU-based (starts at ~$25/month for 400 RU/s) |
| **Best for** | When you already use Cosmos DB for other data |
| **Limitation** | More complex setup than Azure AI Search for pure search workloads |

### PostgreSQL + pgvector (Azure Database for PostgreSQL)

| Feature | Details |
|---------|---------|
| **Vector support** | pgvector extension, HNSW and IVFFlat indexes |
| **Pricing** | Starts at ~$25/month (Burstable B1ms) |
| **Best for** | Teams already using PostgreSQL, budget-conscious |
| **Limitation** | Self-managed indexing, no built-in AI enrichment pipeline |

### Azure OpenAI Embeddings

| Model | Price per 1M tokens | Deployment |
|-------|---------------------|------------|
| text-embedding-3-small | $0.02 | Pay-as-you-go or PTU |
| text-embedding-3-large | $0.13 | Pay-as-you-go or PTU |
| text-embedding-ada-002 | $0.10 | Pay-as-you-go or PTU |

**Note:** Azure OpenAI embeddings stay within Azure tenant (data sovereignty), support RBAC, and can be deployed in specific regions for compliance.

### Recommended Azure Stack for WOF

```
Azure AI Search (Basic: $74/mo)
    + Azure OpenAI text-embedding-3-small ($0.02/M tokens)
    + Integrated AI enrichment pipeline
    = ~$80/month for typical WOF project
```

This provides: managed vector + keyword hybrid search, automatic indexing pipeline, REST API for MCP integration, enterprise compliance (data stays in tenant).

---

## 6. Local/Lightweight Options

For WOF installations that need to work offline, in air-gapped environments, or without cloud costs.

### sqlite-vec

| Feature | Details |
|---------|---------|
| **Type** | SQLite extension for vector search |
| **Storage** | Single file (`.db`), portable |
| **Installation** | `pip install sqlite-vec` or pre-built binaries |
| **Dimensions** | Configurable |
| **Index type** | Brute-force (small datasets) or IVF (larger) |
| **Best for** | WOF's local-first approach - single file, zero infrastructure |
| **Limitation** | Performance degrades past ~1M vectors without careful tuning |

**Why sqlite-vec for WOF:** Aligns with WOF's "single config file" pattern. The index is a single `.db` file in `.ai/` that can be gitignored. No server process needed. PowerShell can interact via `System.Data.SQLite`.

### ChromaDB

| Feature | Details |
|---------|---------|
| **Type** | Open-source embedding database |
| **Storage** | Local (persistent mode) or client-server |
| **Installation** | `pip install chromadb` |
| **API** | Python, JavaScript, REST |
| **Best for** | Rapid prototyping, development environments |
| **Limitation** | Requires Python runtime, heavier than sqlite-vec |

### Qdrant

| Feature | Details |
|---------|---------|
| **Type** | Vector database (Rust-based) |
| **Storage** | Local binary or Docker container |
| **Installation** | Docker: `docker run qdrant/qdrant` |
| **API** | REST, gRPC, Python, JavaScript |
| **Performance** | Excellent for large datasets (millions of vectors) |
| **Best for** | Teams needing high-performance local vector search |
| **Limitation** | Requires Docker or binary installation, more operational overhead |

### FAISS (Facebook AI Similarity Search)

| Feature | Details |
|---------|---------|
| **Type** | Library for efficient similarity search |
| **Storage** | In-memory or memory-mapped files |
| **Installation** | `pip install faiss-cpu` or `faiss-gpu` |
| **Performance** | Extremely fast, GPU-accelerated option |
| **Best for** | Large-scale batch indexing, research |
| **Limitation** | Library (not database), no built-in persistence, requires Python |

### LanceDB

| Feature | Details |
|---------|---------|
| **Type** | Embedded vector database (used by Continue.dev) |
| **Storage** | Local files, columnar format |
| **Installation** | `pip install lancedb` or npm package |
| **API** | Python, JavaScript/TypeScript |
| **Best for** | Embedded use in tools (proven by Continue.dev at scale) |
| **Limitation** | Newer project, smaller community than alternatives |

### Recommendation for WOF Local

**Primary:** `sqlite-vec` - Aligns with WOF's PowerShell + JSON config architecture. Single file, no server, works offline. Can be accessed from PowerShell via SQLite bindings.

**Alternative:** `LanceDB` - If building a Node.js/TypeScript MCP server (proven in Continue.dev for codebases up to 10M lines).

---

## 7. Existing MCP Servers

Ready-to-use MCP servers that provide code indexing for Claude Code.

### Top Candidates for WOF

| Server | Stars | Backend | Embeddings | Languages | Maturity |
|--------|-------|---------|------------|-----------|----------|
| **Claude Context** (Zilliz) | 5,400 | Milvus / Zilliz Cloud | OpenAI, Voyage, Ollama, Gemini | Multi-language | Mature |
| **Code Index MCP** (johnhuang316) | 783 | Local cache (no vector DB) | None (AST-based) | 50+ (tree-sitter + fallback) | Active |
| **DeepContext** (Wildcard) | 265 | Jina embeddings | Jina (1024-dim) | TypeScript, Python only | Early |
| **CodeGrok** (dondetir) | - | Local `.codegrok/` | nomic CodeRankEmbed (768-dim) | 9 languages | Active |
| **CocoIndex Code** (cocoindex-io) | 57 | Local SentenceTransformers | all-MiniLM-L6-v2 (swappable to 100+ models) | 29+ languages | Early |
| **Code-Index-MCP** (ViperJuice) | 36 | SQLite + FTS5, optional Voyage | Optional (Voyage AI) | 48 languages (tree-sitter) | MVP |

### Detailed Analysis of Top 3

#### Claude Context (by Zilliz) - Recommended for Tier 1

- **Architecture:** Hybrid BM25 + dense vector search via Milvus
- **Key features:** `index_codebase`, `search_code`, `clear_index`, `get_indexing_status`
- **Token savings:** ~40% reduction with equivalent retrieval quality
- **Change detection:** Merkle tree tracking for incremental file updates
- **Embedding flexibility:** OpenAI, Voyage AI, Ollama (local), Gemini
- **Installation:** `npx -y @anthropic-ai/claude-code mcp add claude-context -- npx -y @anthropic-ai/claude-context-mcp`
- **Requirement:** Node.js 20.x-23.x (incompatible with 24.0.0+)
- **License:** MIT

**Why for WOF:** Most mature, largest community, supports both cloud and local embeddings (Ollama), hybrid search matches industry best practice, MIT licensed.

#### CocoIndex Code (by cocoindex-io) - Best Local Alternative

- **Architecture:** Rust-based engine, tree-sitter AST parsing, local embeddings
- **Key features:** Zero-config setup (auto-discovers via `.git/`), 29+ languages
- **Token savings:** ~70% claimed
- **Default embedding:** all-MiniLM-L6-v2 (local, no API key needed)
- **Optional:** 100+ cloud embedding models via LiteLLM
- **License:** Open source

**Why for WOF:** Zero-config, local-first, no API keys needed by default, wide language support, aligns with WOF's "works out of the box" philosophy.

#### Code-Index-MCP (by ViperJuice) - Best Modular Option

- **Architecture:** SQLite + FTS5 for keyword search, optional Voyage AI for semantic
- **Key features:** 48 languages, git sync, plugin-based, portable indexes via GitHub Artifacts
- **Three tiers:** Minimal (no API), Standard ($0.05/M tokens), Full
- **Performance targets:** <100ms symbol lookup, <500ms search, <10s cached repo index
- **License:** MIT

**Why for WOF:** Tiered configuration matches WOF's approach, SQLite aligns with local-first, modular plugin system could be extended.

### Other Notable MCP Servers

| Server | Notes |
|--------|-------|
| **Context7** (Upstash, 46.5k stars) | Library documentation search, NOT codebase indexing - useful but different purpose |
| **tree-sitter-mcp** (wrale) | AST analysis without embeddings - structural code navigation |
| **FileScopeMCP** (admica) | Dependency analysis and file importance scoring - complementary tool |
| **Code Index MCP** (trondhindenes) | Zoekt trigram-based search - fast but no semantic understanding |

---

## 8. Recommendation for WOF

### Tiered Implementation Strategy

#### Tier 1: Quick Win (Recommended First Step)

**Goal:** Add semantic code search to any WOI project in minutes.

**Approach:** Integrate Claude Context MCP (or CocoIndex Code) as an optional WOF extension, configurable via `/wof configure`.

**Implementation:**
1. New config file: `.ai/config/index.json` - stores indexing preferences (provider, embedding model, scope)
2. New `/wof configure` menu option: `[4] Configure Code Index`
   - Choice: Claude Context MCP (cloud embeddings) or CocoIndex Code (local embeddings)
   - Auto-configure MCP server in `.mcp.json`
   - Test connection
3. New `/wof index` command: `index`, `index status`, `index clear`
4. Update WOI-SECTION.md with indexing guidance for agents

**Config example (`index.json`):**
```json
{
  "version": "1.0.0",
  "enabled": false,
  "provider": "claude-context",
  "embedding": {
    "model": "text-embedding-3-small",
    "provider": "openai"
  },
  "scope": {
    "include": ["src/**", "lib/**"],
    "exclude": ["node_modules/**", "dist/**", "*.min.js"]
  }
}
```

**Files to create/modify in WOF:**
| File | Action |
|------|--------|
| `templates/config/index.json.template` | Create - Index configuration template |
| `templates/dot-claude/skills/wof/SKILL.md` | Edit - Add `/wof index` commands |
| `core/scripts/configure-index.ps1` | Create - Index configuration wizard |
| `templates/WOI-SECTION.md` | Edit - Add indexing section |
| `setup.ps1` | Edit - Deploy index.json template |
| `sync-manifest.json` | Edit - Add index.json to template_only |

**Estimated effort:** 2-3 days
**Value:** Immediate semantic search for all WOI projects

---

#### Tier 2: WOF-Native Index Module

**Goal:** Build WOF's own indexing system with deep integration into the multi-agent workflow.

**Approach:** A WOF-managed index that:
- Automatically indexes on `/wof start`
- Is aware of WOF's project structure (`.ai/`, `src/`, tests)
- Provides role-specific search (Orchestrator gets architecture, Workers get implementation details)
- Uses configurable backend: sqlite-vec (local default) or Azure AI Search (enterprise)

**Architecture:**
```
/wof start
  └── Index Check
       ├── No index → Full index (background)
       ├── Stale index → Incremental update
       └── Fresh index → Skip
            └── MCP Server (wof-index)
                 ├── search_code (semantic)
                 ├── search_symbols (AST-based)
                 ├── get_context (file + dependencies)
                 └── index_status
```

**Backend options:**
- **Local:** sqlite-vec + all-MiniLM-L6-v2 (zero cost, offline capable)
- **Cloud:** Azure AI Search + Azure OpenAI embeddings (~$80/month)
- **Hybrid:** Local for development, Azure for CI/CD and shared team access

**Estimated effort:** 2-3 weeks
**Value:** Deep WOF integration, role-aware search, configurable backend

---

#### Tier 3: Enterprise Deployment

**Goal:** One-click Azure infrastructure deployment for team-wide shared code index.

**Approach:** ARM/Bicep templates that deploy:
- Azure AI Search (Basic or S1 tier)
- Azure OpenAI embeddings endpoint
- Indexer pipeline (Azure Function or Logic App)
- Optional: Azure DevOps pipeline for automatic re-indexing on push

**Architecture:**
```
Developer Machine (WOI)
  └── MCP Server → Azure AI Search REST API
                      ├── Vector index (embeddings)
                      ├── Keyword index (BM25)
                      └── Semantic ranker

Azure Resources (Bicep deployment)
  ├── Azure AI Search (Basic: $74/mo)
  ├── Azure OpenAI (text-embedding-3-small: $0.02/M tokens)
  ├── Azure Function (indexer trigger)
  └── Azure DevOps webhook (re-index on push)
```

**Config via `/wof configure`:**
```
[4] Configure Code Index
    [1] Local (sqlite-vec, free, offline)
    [2] Cloud (Azure AI Search, shared team index)
    [3] Deploy Azure infrastructure (ARM/Bicep)
    [B] Back
```

**Estimated effort:** 2-3 weeks (after Tier 2)
**Value:** Enterprise-grade shared index, team collaboration, compliance-ready

---

### Decision Matrix

| Factor | Tier 1 (MCP Server) | Tier 2 (WOF-Native) | Tier 3 (Enterprise) |
|--------|---------------------|----------------------|---------------------|
| **Setup time** | Minutes | Hours (first time) | Hours (infra deploy) |
| **Cost** | Free (local) or ~$0.02/M tokens | Free (local) or ~$80/mo | ~$80-250/month |
| **Offline** | Depends on MCP server | Yes (sqlite-vec) | No (Azure required) |
| **Team sharing** | No | No | Yes |
| **WOF integration** | Shallow (MCP tools) | Deep (role-aware) | Deep + shared |
| **Maintenance** | MCP server updates | WOF manages | Azure manages |

---

## 9. Next Steps

### Immediate (Tier 1 Implementation)

Create the following ADO work items:

1. **Create `index.json.template`** - Configuration template for code indexing preferences
2. **Create `configure-index.ps1`** - Interactive wizard for `/wof configure` index menu
3. **Add `/wof index` commands to SKILL.md** - `index`, `index status`, `index clear`
4. **Update `setup.ps1` and `sync.ps1`** - Deploy and sync index configuration
5. **Update WOI-SECTION.md** - Add indexing guidance for agents
6. **Test with Claude Context MCP and CocoIndex Code** - Verify both work as expected

### Future (Tier 2/3 Evaluation)

7. **Prototype WOF-native index with sqlite-vec** - Evaluate feasibility of PowerShell + SQLite vector search
8. **Design ARM/Bicep templates for Azure AI Search** - Enterprise deployment automation
9. **Benchmark: MCP server vs native index** - Compare search quality, latency, token savings

### Research to Revisit

- Monitor Claude Code releases for native indexing support (would make Tier 2/3 unnecessary)
- Track MCP server ecosystem maturity (new entrants appear monthly)
- Evaluate LanceDB as alternative to sqlite-vec (proven at scale in Continue.dev)

---

## Appendix A: MCP Server Installation Quick Reference

### Claude Context (Recommended)
```bash
# Install
claude mcp add claude-context -- npx -y @anthropic-ai/claude-context-mcp

# Requires: Node.js 20.x-23.x, embedding API key (OpenAI/Voyage/Ollama)
```

### CocoIndex Code (Local Alternative)
```bash
# Install
pip install cocoindex-code
claude mcp add cocoindex-code -- cocoindex-code serve

# Requires: Python 3.10+, no API key needed (uses local all-MiniLM-L6-v2)
```

### CodeGrok (Fully Offline)
```bash
# Install
pip install codegrok-mcp
claude mcp add codegrok -- codegrok serve

# Requires: Python 3.10+, no API key, uses nomic CodeRankEmbed locally
```

## Appendix B: Cost Estimates

### Per-Project Embedding Costs (One-Time Indexing)

| Codebase Size | Tokens (est.) | text-embedding-3-small | voyage-code-3 |
|---------------|---------------|----------------------|----------------|
| Small (10k LOC) | ~500K tokens | $0.01 | $0.11 |
| Medium (100k LOC) | ~5M tokens | $0.10 | $1.10 |
| Large (1M LOC) | ~50M tokens | $1.00 | $11.00 |
| Monorepo (10M LOC) | ~500M tokens | $10.00 | $110.00 |

### Monthly Infrastructure Costs

| Setup | Monthly Cost | Includes |
|-------|-------------|----------|
| **Local only** (sqlite-vec + local embeddings) | $0 | Free, offline capable |
| **Cloud embeddings only** (OpenAI small) | ~$1-10 | Depends on re-indexing frequency |
| **Azure AI Search Basic** | ~$74 + embeddings | Managed search, 15 GB storage |
| **Azure AI Search S1** | ~$245 + embeddings | Production, 160 GB, 50 indexes |
| **Full Azure stack** (Search + OpenAI + Function) | ~$100-300 | Enterprise, automated pipeline |
