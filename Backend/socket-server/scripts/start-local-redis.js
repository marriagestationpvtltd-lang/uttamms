'use strict';

const { RedisMemoryServer } = require('redis-memory-server');

async function main() {
  const port = parseInt(process.env.REDIS_PORT || '6379', 10);
  const ip = process.env.REDIS_HOST || '127.0.0.1';

  const redisServer = await RedisMemoryServer.create({
    instance: {
      port,
      ip,
    },
    autoStart: true,
  });

  const host = await redisServer.getHost();
  const actualPort = await redisServer.getPort();

  console.log(`✅ Local Redis started at redis://${host}:${actualPort}`);
  console.log('ℹ️  Keep this process running while socket-server is active.');

  const shutdown = async () => {
    try {
      console.log('\n🛑 Stopping local Redis...');
      await redisServer.stop();
      console.log('✅ Local Redis stopped');
      process.exit(0);
    } catch (err) {
      console.error('❌ Failed to stop local Redis:', err?.message || err);
      process.exit(1);
    }
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  console.error('❌ Failed to start local Redis:', err?.message || err);
  process.exit(1);
});
