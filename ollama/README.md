# Ollama Deployment - The Artisan's Field Forge

This directory contains the configuration for deploying Ollama with pre-baked Gemma models to Google Cloud Run with GPU acceleration.

## Overview

The Ollama deployment provides a simple, developer-friendly LLM endpoint that's perfect for rapid prototyping and development. The key innovation is "baking" the model directly into the container image during build time, which dramatically improves cold start performance.

## Architecture

```
┌─────────────────────────────────────┐
│         Build Phase                  │
│  ┌─────────────────────────────┐    │
│  │  Base: ollama/ollama         │    │
│  └──────────┬──────────────────┘    │
│             │                        │
│  ┌──────────▼──────────────────┐    │
│  │  Download & Bake Models:     │    │
│  │  - gemma:2b                  │    │
│  │  - gemma2:2b (optional)      │    │
│  │  - qwen2.5:3b (optional)     │    │
│  └──────────┬──────────────────┘    │
│             │                        │
│  ┌──────────▼──────────────────┐    │
│  │  Final Image with Models     │    │
│  │  (~8-10GB)                   │    │
│  └─────────────────────────────┘    │
└─────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│         Cloud Run Service            │
│  ┌─────────────────────────────┐    │
│  │  GPU: NVIDIA L4               │    │
│  │  Memory: 16Gi                 │    │
│  │  CPU: 4 cores                 │    │
│  │  Port: 11434                  │    │
│  └─────────────────────────────┘    │
└─────────────────────────────────────┘
```

## Files

- **Dockerfile**: Advanced multi-stage build with model pre-loading
- **Dockerfile.simple**: Basic version with single model (gemma:2b)
- **docker-compose.yml**: Local testing configuration
- **cloudbuild-ollama-deploy.yaml**: Full Cloud Build pipeline
- **deploy-ollama-baked.sh**: Automated deployment script

## Quick Deploy

### Option 1: Using Make (Recommended)

```bash
# From project root
make deploy-ollama        # Deploy with multiple models
make deploy-ollama-simple # Deploy with single model
make test-ollama         # Test the deployed service
```

### Option 2: Direct Script

```bash
cd ollama
./deploy-ollama-baked.sh           # Multiple models
./deploy-ollama-baked.sh --simple   # Single model only
```

### Option 3: Manual Cloud Build

```bash
source ../set_env.sh
gcloud builds submit \
  --config cloudbuild-ollama-deploy.yaml \
  --substitutions=_REGION="$REGION" \
  .
```

## Local Testing

Test the Ollama container locally before deploying:

```bash
# Build and run with docker-compose
docker-compose up --build

# Test the local instance
curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma:2b",
    "prompt": "Hello, world!",
    "stream": false
  }'
```

## API Usage

### Generate Text

```bash
curl -X POST "$OLLAMA_URL/api/generate" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma:2b",
    "prompt": "Explain quantum computing",
    "stream": false,
    "options": {
      "temperature": 0.7,
      "top_p": 0.9,
      "max_tokens": 500
    }
  }'
```

### List Available Models

```bash
curl "$OLLAMA_URL/api/tags"
```

### Chat Completion

```bash
curl -X POST "$OLLAMA_URL/api/chat" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma:2b",
    "messages": [
      {"role": "user", "content": "What is the capital of France?"}
    ],
    "stream": false
  }'
```

## Performance Characteristics

### Advantages
- **Fast Cold Starts**: Model is pre-baked into image (~10-15 seconds vs 2-3 minutes)
- **Simple Deployment**: No model management required
- **Developer Friendly**: Standard Ollama API
- **Predictable**: Same model version every time

### Trade-offs
- **Large Image Size**: ~8-10GB per image
- **Model Updates**: Requires full rebuild and redeploy
- **Fixed Models**: Can't dynamically load new models
- **Storage Costs**: Higher due to image size

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_HOST` | `0.0.0.0:11434` | Binding address |
| `OLLAMA_NUM_PARALLEL` | `4` | Parallel request handling |
| `OLLAMA_KEEP_ALIVE` | `24h` | Model memory retention |
| `OLLAMA_MAX_LOADED_MODELS` | `2` | Max models in memory |

### GPU Configuration

The service runs on NVIDIA L4 GPUs by default. Modify in cloudbuild.yaml:
- `--gpu-type=nvidia-l4` (options: nvidia-l4, nvidia-a100-80gb)
- `--gpu=1` (number of GPUs)

### Scaling

Configured for auto-scaling:
- Min instances: 1 (always warm)
- Max instances: 2 (cost control)
- Concurrency: 4 requests per instance

## Monitoring

Check service health:
```bash
gcloud run services describe gemma-ollama-baked-service \
  --region=$REGION \
  --format="table(status.conditions.type,status.conditions.status)"
```

View logs:
```bash
gcloud logging read "resource.type=cloud_run_revision \
  AND resource.labels.service_name=gemma-ollama-baked-service" \
  --limit=50
```

## Troubleshooting

### Service Not Responding
1. Check if the service is running: `make status`
2. Verify GPU allocation: Check Cloud Run console
3. Review logs: `gcloud logging read ...`

### Model Not Found
- Ensure model was properly baked during build
- Check Dockerfile includes correct `ollama pull` command
- Verify image was built successfully

### High Latency
- Check if using GPU (not CPU)
- Verify `--no-cpu-throttling` is set
- Consider increasing memory allocation

## Cost Optimization

- Use `--max-instances=1` for dev environments
- Enable scale-to-zero for non-production
- Consider using spot instances for batch workloads
- Monitor usage with Cloud Monitoring

## Next Steps

After deploying Ollama, you can:
1. Deploy vLLM for production workloads
2. Set up the Guardian Agent to use this endpoint
3. Configure monitoring and alerting
4. Implement authentication if needed