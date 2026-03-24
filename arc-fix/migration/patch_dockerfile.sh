#!/bin/bash

echo "🔧 Applying immediate fix to Dockerfile..."
echo ""

# First, stop and clean up
docker-compose down 2>/dev/null
docker-compose rm -f 2>/dev/null

# Update the bullmq-exporter Dockerfile
cat > bullmq-exporter/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install --production --omit=optional --no-optional

COPY index.js ./

EXPOSE 3000

CMD ["npm", "start"]
EOF

echo "✅ Updated bullmq-exporter/Dockerfile"

# Update the bullmq-exporter package.json
cat > bullmq-exporter/package.json << 'EOF'
{
  "name": "bullmq-metrics-exporter",
  "version": "1.0.0",
  "description": "BullMQ Prometheus metrics exporter",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "bullmq": "5.28.2",
    "ioredis": "5.4.1"
  }
}
EOF

echo "✅ Updated bullmq-exporter/package.json"

# Update the index.js to use http instead of express
cat > bullmq-exporter/index.js << 'EOF'
const http = require('http');
const { Queue } = require('bullmq');

const PORT = process.env.PORT || 3000;
const REDIS_HOST = process.env.REDIS_HOST || 'localhost';
const REDIS_PORT = process.env.REDIS_PORT || 6379;

// Connection configuration
const connection = {
  host: REDIS_HOST,
  port: REDIS_PORT,
};

// Store queue instances
const queues = new Map();

// Function to get or create a queue instance
function getQueue(queueName) {
  if (!queues.has(queueName)) {
    const queue = new Queue(queueName, { connection });
    queues.set(queueName, queue);
  }
  return queues.get(queueName);
}

// Discover queues from Redis
async function discoverQueues() {
  try {
    const Redis = require('ioredis');
    const redis = new Redis(connection);

    // Find all BullMQ queues
    const keys = await redis.keys('bull:*:meta');
    const queueNames = new Set();

    keys.forEach(key => {
      const match = key.match(/^bull:([^:]+):meta$/);
      if (match) {
        queueNames.add(match[1]);
      }
    });

    await redis.quit();
    return Array.from(queueNames);
  } catch (error) {
    console.error('Error discovering queues:', error);
    return [];
  }
}

// Create HTTP server
const server = http.createServer(async (req, res) => {
  try {
    // Metrics endpoint
    if (req.url === '/metrics' && req.method === 'GET') {
      const queueNames = await discoverQueues();

      if (queueNames.length === 0) {
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        return res.end('# No queues found\n');
      }

      let allMetrics = '';

      // Gather metrics from all discovered queues
      for (const queueName of queueNames) {
        try {
          const queue = getQueue(queueName);
          const metrics = await queue.exportPrometheusMetrics();
          allMetrics += metrics + '\n';
        } catch (error) {
          console.error(`Error getting metrics for queue ${queueName}:`, error);
        }
      }

      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end(allMetrics);
    }
    // Health check endpoint
    else if (req.url === '/health' && req.method === 'GET') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'ok' }));
    }
    // List discovered queues
    else if (req.url === '/queues' && req.method === 'GET') {
      const queueNames = await discoverQueues();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ queues: queueNames }));
    }
    // 404 Not Found
    else {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
    }
  } catch (error) {
    console.error('Request error:', error);
    res.writeHead(500, { 'Content-Type': 'text/plain' });
    res.end(`Error: ${error.message}`);
  }
});

server.listen(PORT, () => {
  console.log(`BullMQ Prometheus metrics exporter running on port ${PORT}`);
  console.log(`Metrics available at http://localhost:${PORT}/metrics`);
  console.log(`Health check at http://localhost:${PORT}/health`);
  console.log(`Queue list at http://localhost:${PORT}/queues`);
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM signal received: closing HTTP server');
  server.close();
  for (const queue of queues.values()) {
    await queue.close();
  }
  process.exit(0);
});
EOF

echo "✅ Updated bullmq-exporter/index.js"
echo ""
echo "🚀 Now rebuilding Docker images..."
docker-compose build --no-cache bullmq-metrics

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build successful!"
    echo ""
    echo "Starting services..."
    docker-compose up -d

    if [ $? -eq 0 ]; then
        echo ""
        echo "╔════════════════════════════════════════╗"
        echo "║  ✅ Fix Applied Successfully!         ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        echo "Services are now running:"
        docker-compose ps
        echo ""
        echo "Continue with step 2:"
        echo "  npm install --omit=optional"
    else
        echo "❌ Failed to start services"
    fi
else
    echo "❌ Build failed"
    echo ""
    echo "Try running manually:"
    echo "  docker-compose build --no-cache"
fi
EOF