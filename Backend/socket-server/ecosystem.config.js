// PM2 ecosystem config — runs multiple Node.js instances behind the
// @socket.io/redis-adapter so every instance shares rooms/events.
//
// Usage:
//   npm install -g pm2
//   cp .env.example .env      # fill in real values
//   npm install               # install production dependencies
//   pm2 start ecosystem.config.js --env production
//   pm2 save                  # persist across reboots
//   pm2 startup               # generate OS init script
//
// To scale up or down at runtime (no downtime):
//   pm2 scale socket-server 8
//
// To view logs:
//   pm2 logs socket-server

'use strict';

module.exports = {
  apps: [
    {
      name: 'socket-server',
      script: './server.js',

      // Number of instances.  'max' uses all available CPU cores.
      // For a 4-core machine this runs 4 processes (~1000 concurrent
      // WebSocket connections per process = 4000+ total).
      // Increase or set to a specific number to match your hardware.
      instances: process.env.WEB_CONCURRENCY || 'max',

      // cluster mode: PM2 load-balances TCP connections across instances.
      // Combined with the Redis adapter, all instances share Socket.IO state.
      exec_mode: 'cluster',

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
