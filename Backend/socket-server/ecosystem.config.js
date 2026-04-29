// PM2 ecosystem config — runs a single Node.js instance by default.
//
// ⚠️  IMPORTANT — MULTI-INSTANCE / CLUSTER MODE:
// The Socket.IO server does NOT implement the @socket.io/redis-adapter.
// Running more than one instance (exec_mode: 'cluster') without a shared
// Redis pub/sub adapter causes Socket.IO rooms to be PROCESS-LOCAL, which
// means a message emitted on instance A will NOT reach a user whose WebSocket
// is connected to instance B.  Enabling cluster mode without Redis will cause
// intermittent message delivery failures.
//
// If you need horizontal scaling, install @socket.io/redis-adapter and ioredis,
// configure REDIS_* variables in .env, and update server.js to use the adapter
// BEFORE enabling cluster mode.
//
// Usage:
//   npm install -g pm2
//   cp .env.example .env      # fill in real values
//   npm install               # install production dependencies
//   pm2 start ecosystem.config.js --env production
//   pm2 save                  # persist across reboots
//   pm2 startup               # generate OS init script
//
// To view logs:
//   pm2 logs socket-server

'use strict';

module.exports = {
  apps: [
    {
      name: 'socket-server',
      script: './server.js',

      // Number of instances.
      // Defaults to 1 (safe single-instance mode) because the server does not
      // implement a Redis adapter.  With a single instance all Socket.IO rooms
      // are in-process and every connected user receives real-time events.
      // Set WEB_CONCURRENCY to a higher number only after you have configured
      // the Redis adapter in server.js (see comment at the top of this file).
      instances: process.env.WEB_CONCURRENCY || 1,

      // 'fork' mode runs a single process.  Switch to 'cluster' only when the
      // Redis adapter is in place so Socket.IO state is shared across workers.
      exec_mode: 'fork',

      // Automatically restart on crash
      autorestart: true,

      // Restart when memory exceeds 512 MB (adjust to your server RAM)
      max_memory_restart: '512M',

      // Watch for changes in development (disable in production)
      watch: false,

      // Pass the .env file
      env_file: '.env',

      env_production: {
        NODE_ENV: 'production',
      },

      env_development: {
        NODE_ENV: 'development',
        PORT: 3001,
      },

      // Log files
      out_file: './logs/out.log',
      error_file: './logs/error.log',
      merge_logs: true,
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    },
  ],
};
