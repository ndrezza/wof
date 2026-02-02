# Ollama Setup Guide

This guide covers installing and configuring Ollama for use with WOF local AI features.

## What is Ollama?

[Ollama](https://ollama.com) is a local LLM runtime that makes it easy to run open-source models on your machine. As of v0.14.0, Ollama has **native Anthropic Messages API compatibility**, meaning it works directly with Claude Code without a proxy.

## Installation

### Windows

1. **Download the installer** from [ollama.com/download/windows](https://ollama.com/download/windows)
2. Run the `.exe` installer
3. Ollama runs as a background service automatically

**Alternative (winget):**
```powershell
winget install Ollama.Ollama
```

### macOS

1. **Download the app** from [ollama.com/download/mac](https://ollama.com/download/mac)
2. Drag to Applications folder
3. Launch Ollama (runs in menu bar)

**Alternative (Homebrew):**
```bash
brew install ollama
```

### Linux

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

This installs Ollama and sets up a systemd service.

**Manual install (if curl method fails):**
1. Download from [ollama.com/download/linux](https://ollama.com/download/linux)
2. Extract and run `./ollama serve`

## Verify Installation

After installation, verify Ollama is running:

```bash
# Check version
ollama --version

# Check API is responding
curl http://localhost:11434/api/tags

# Or on Windows PowerShell
Invoke-RestMethod http://localhost:11434/api/tags
```

Expected: Version number and empty model list (or list of models if you've pulled some).

## Pulling Models

Models must be downloaded before use:

```bash
# Pull a model
ollama pull qwen3-coder:30b

# Pull with specific quantization
ollama pull llama3.1:8b-instruct-q4_K_M
```

### Recommended Models by Hardware

| RAM Available | Recommended Model | Notes |
|---------------|-------------------|-------|
| **8GB** | `deepseek-r1:8b` | Good reasoning, fits in memory |
| **8GB** | `llama3.1:8b-instruct-q4_K_M` | General purpose, quantized |
| **16GB** | `qwen3-coder:14b` | Excellent for code |
| **16GB** | `deepseek-r1:14b` | Better reasoning than 8b |
| **32GB+** | `qwen3-coder:30b` | Best code quality |
| **32GB+** | `codellama:34b` | Strong code completion |
| **48GB+** | `qwen3-coder:72b` | Maximum quality |

**Rule of thumb:** Model requires ~1.2x its parameter count in GB of RAM for q4 quantization.
- 8B model ≈ 10GB RAM
- 14B model ≈ 17GB RAM
- 30B model ≈ 36GB RAM

### Models for Specific Tasks

| Task | Recommended Model | Why |
|------|-------------------|-----|
| **Code generation** | `qwen3-coder:30b` | Trained specifically for code |
| **Reasoning/planning** | `deepseek-r1:14b` | Strong reasoning capabilities |
| **General assistant** | `llama3.1:8b-instruct` | Good all-around performance |
| **Fast responses** | `qwen3:4b` | Small, quick inference |

## Model Management

```bash
# List downloaded models
ollama list

# Show model details (size, quantization, etc.)
ollama show qwen3-coder:30b

# Remove a model
ollama rm codellama:34b

# Copy/rename a model
ollama cp qwen3-coder:30b my-coder

# Update a model to latest
ollama pull qwen3-coder:30b
```

## GPU Acceleration

Ollama automatically detects and uses GPU acceleration:

| Platform | GPU Support | Detection |
|----------|-------------|-----------|
| **NVIDIA** | CUDA | Automatic |
| **AMD** | ROCm (Linux) | Automatic |
| **Apple Silicon** | Metal | Automatic |
| **Intel** | Limited | Varies |

### Verify GPU is Being Used

```bash
# Check Ollama logs for GPU detection
# Windows: Check Event Viewer or Ollama tray icon
# macOS: Check Console.app
# Linux:
journalctl -u ollama -f

# NVIDIA: Monitor GPU usage during inference
nvidia-smi -l 1
```

### Force CPU-Only (if needed)

```bash
# Linux/macOS
CUDA_VISIBLE_DEVICES="" ollama serve

# Windows PowerShell
$env:CUDA_VISIBLE_DEVICES = ""
ollama serve
```

## Running Ollama

### As a Service (Recommended)

Ollama typically runs as a background service:

- **Windows:** Starts automatically, runs in system tray
- **macOS:** Runs in menu bar when app is open
- **Linux:** Managed by systemd (`sudo systemctl status ollama`)

### Manual Start

If the service isn't running:

```bash
# Start Ollama server
ollama serve

# Run in background (Linux/macOS)
ollama serve &
```

### Custom Host/Port

```bash
# Change listen address
OLLAMA_HOST=0.0.0.0:11434 ollama serve

# Windows PowerShell
$env:OLLAMA_HOST = "0.0.0.0:11434"
ollama serve
```

## Using with WOF

Once Ollama is running with a model, configure WOF to use it:

### Option 1: Environment Variables

```bash
# Linux/macOS
export ANTHROPIC_BASE_URL="http://localhost:11434"
export ANTHROPIC_API_KEY="ollama"
claude
```

```powershell
# Windows PowerShell
$env:ANTHROPIC_BASE_URL = "http://localhost:11434"
$env:ANTHROPIC_API_KEY = "ollama"
claude
```

### Option 2: MCP Server with Ollama Backend

Register an MCP server that routes to Ollama:

```bash
claude mcp add --scope local local-worker \
  -e ANTHROPIC_BASE_URL=http://localhost:11434 \
  -e ANTHROPIC_API_KEY=ollama \
  -- claude mcp serve
```

### Option 3: Use WOF Launchers

After running `/wof configure` with Ollama, use the generated launcher:

```powershell
# Windows
.\.ai\launchers\Start-ClaudeLocal.ps1

# Linux/macOS
./.ai/launchers/start-claude-local.sh
```

## Troubleshooting

### "Connection refused" or "Cannot connect"

Ollama isn't running:

```bash
# Start the service
ollama serve

# Or check service status (Linux)
sudo systemctl status ollama
sudo systemctl start ollama
```

### "Model not found"

The model hasn't been pulled:

```bash
# List available models
ollama list

# Pull the model
ollama pull qwen3-coder:30b
```

### Slow Inference

1. **Check GPU usage** - If GPU isn't being used, inference is CPU-bound
2. **Use a smaller model** - 8B models are much faster than 30B+
3. **Use quantized versions** - `q4_K_M` is faster than `f16`
4. **Close other applications** - Free up RAM and GPU memory

### Out of Memory

Model is too large for available RAM:

```bash
# Use a smaller model
ollama pull deepseek-r1:8b

# Or use more aggressive quantization
ollama pull qwen3-coder:14b-q4_0
```

### "CUDA out of memory" (NVIDIA)

GPU VRAM is full:

1. Use a smaller model
2. Close other GPU applications
3. Set layers to offload: `OLLAMA_NUM_GPU=20 ollama serve`

### Unicode/Encoding Errors (Windows)

```powershell
$env:PYTHONIOENCODING = "utf-8"
```

## Context Window Considerations

Different models have different context limits:

| Model | Context Window |
|-------|----------------|
| `llama3.1:8b` | 128k tokens |
| `qwen3-coder:30b` | 32k tokens |
| `deepseek-r1:14b` | 64k tokens |
| `codellama:34b` | 16k tokens |

For WOF tasks requiring large context (reading many files), choose models with 64k+ context windows.

## Performance Tips

1. **Keep Ollama running** - First inference loads model into memory; subsequent calls are faster
2. **Use the right model size** - Bigger isn't always better; match to your hardware
3. **GPU acceleration** - Ensures best performance; verify it's active
4. **SSD storage** - Models load faster from SSD than HDD
5. **Sufficient RAM** - Model + ~4GB overhead for system

## Resources

- [Ollama Documentation](https://github.com/ollama/ollama/blob/main/README.md)
- [Ollama Model Library](https://ollama.com/library)
- [Ollama API Reference](https://github.com/ollama/ollama/blob/main/docs/api.md)
- [WOF MCP Agent Setup](./mcp-agent-setup.md) - Configuring Ollama with WOF MCP servers
