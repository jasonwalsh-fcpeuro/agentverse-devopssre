# Multi-stage build for Ollama with pre-loaded models
FROM ollama/ollama:latest AS builder

# Set environment variables
ENV OLLAMA_HOST=0.0.0.0:11434
ENV OLLAMA_MODELS=/root/.ollama/models

# Create a startup script that pulls models
RUN mkdir -p /scripts
RUN cat << 'EOF' > /scripts/init-models.sh
#!/bin/bash
set -e

echo "Starting Ollama server..."
ollama serve &
SERVER_PID=$!

# Wait for Ollama to be ready
echo "Waiting for Ollama to start..."
for i in {1..30}; do
    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "Ollama is ready!"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 2
done

# Pull models
echo "Pulling models..."
ollama pull gemma:2b || echo "Warning: Failed to pull gemma:2b"
ollama pull gemma2:2b || echo "Warning: Failed to pull gemma2:2b"
ollama pull qwen2.5:3b || echo "Warning: Failed to pull qwen2.5:3b"

# List available models
echo "Available models:"
ollama list

# Keep the server running if this is the main process
if [ "$1" = "serve" ]; then
    wait $SERVER_PID
else
    # Stop the server for build stage
    kill $SERVER_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true
fi
EOF

RUN chmod +x /scripts/init-models.sh

# Pre-pull models during build (optional - comment out if you want faster builds)
# This will cache the models in the image
RUN /scripts/init-models.sh

# Final stage
FROM ollama/ollama:latest

# Copy pre-downloaded models and scripts from builder
COPY --from=builder /root/.ollama /root/.ollama
COPY --from=builder /scripts /scripts

# Set environment variables
ENV OLLAMA_HOST=0.0.0.0:11434
ENV OLLAMA_MODELS=/root/.ollama/models
ENV OLLAMA_KEEP_ALIVE=24h

# Expose the default Ollama port
EXPOSE 11434

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:11434/api/tags || exit 1

# Use the init script as entrypoint
ENTRYPOINT ["/scripts/init-models.sh"]
CMD ["serve"]