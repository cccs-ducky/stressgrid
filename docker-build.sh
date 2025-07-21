#!/bin/bash

set -e

echo "🚀 Building Stressgrid Docker image..."
docker build -t stressgrid:latest .

echo "✅ Build complete!"
echo ""
echo "Usage examples:"
echo ""
echo "Run coordinator only:"
echo "  docker run -p 8000:8000 -p 9696:9696 stressgrid:latest coordinator"
echo ""
echo "Run generator (connect to coordinator):"
echo "  docker run -e COORDINATOR_URL=ws://coordinator-host:9696 stressgrid:latest generator"
echo ""
echo "Run with docker-compose (coordinator + generator):"
echo "  docker-compose up"
echo ""
echo "Scale generators:"
echo "  docker-compose up --scale generator=3"
echo ""
echo "Access management UI at: http://localhost:8000" 