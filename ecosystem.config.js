// =============================================================================
// Caetutti Dynamics - PM2 Ecosystem Config
// Para correr directamente en VM sin Docker (alternativa)
// O para gestionar procesos dentro del contenedor si se prefiere
// =============================================================================

module.exports = {
  apps: [
    // ---------------------------------------------------------------------------
    // Backend API + Sync Worker (proceso único, worker corre en hilo separado)
    // ---------------------------------------------------------------------------
    {
      name: 'caetutti-backend',
      script: './backend/dist/index.js',
      cwd: '/app',
      interpreter: 'node',
      interpreter_args: '--max-old-space-size=2048',
      env: {
        NODE_ENV: 'production',
        PORT: 4000,
        DATABASE_FILE: '/data/caetutti.db',
        PLAYWRIGHT_BROWSERS_PATH: 0,
        PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH: '/usr/bin/chromium',
        HEADLESS: 'true',
      },
      // Variables de entorno sensibles - cargar desde .env en producción
      // env_file: '.env',

      // Proceso management
      instances: 1,
      exec_mode: 'fork',
      watch: false,
      max_memory_restart: '2G',
      min_uptime: '30s',
      max_restarts: 10,
      restart_delay: 5000,

      // Logging
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      out_file: '/var/log/caetutti/backend-out.log',
      error_file: '/var/log/caetutti/backend-err.log',
      merge_logs: true,
      log_type: 'json',

      // Graceful shutdown
      kill_timeout: 10000,
      wait_ready: true,
      listen_timeout: 30000,

      // Cron restart (opcional - para limpiar memoria)
      // cron_restart: '0 4 * * *',  // 4 AM diario
    },

    // ---------------------------------------------------------------------------
    // Frontend Next.js (standalone server)
    // ---------------------------------------------------------------------------
    {
      name: 'caetutti-frontend',
      script: './frontend/server.js',
      cwd: '/app',
      interpreter: 'node',
      interpreter_args: '--max-old-space-size=512',
      env: {
        NODE_ENV: 'production',
        PORT: 3000,
        NEXT_TELEMETRY_DISABLED: '1',
      },
      instances: 1,
      exec_mode: 'fork',
      watch: false,
      max_memory_restart: '512M',
      min_uptime: '20s',
      max_restarts: 10,
      restart_delay: 3000,

      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      out_file: '/var/log/caetutti/frontend-out.log',
      error_file: '/var/log/caetutti/frontend-err.log',
      merge_logs: true,
      log_type: 'json',

      kill_timeout: 5000,
      wait_ready: true,
      listen_timeout: 20000,
    },

    // ---------------------------------------------------------------------------
    // Nginx (si se corre en host, no en Docker)
    // ---------------------------------------------------------------------------
    // {
    //   name: 'caetutti-nginx',
    //   script: 'nginx',
    //   args: '-g "daemon off;" -c /etc/nginx/nginx.conf',
    //   interpreter: 'none',
    //   instances: 1,
    //   autorestart: true,
    //   max_restarts: 5,
    //   min_uptime: '10s',
    //   log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    //   out_file: '/var/log/caetutti/nginx-out.log',
    //   error_file: '/var/log/caetutti/nginx-err.log',
    // },
  ],

  // ---------------------------------------------------------------------------
  // Deploy configuration (pm2 deploy)
  // ---------------------------------------------------------------------------
  deploy: {
    production: {
      user: 'appuser',
      host: 'tu-ip-oracle',
      ref: 'origin/main',
      repo: 'git@github.com:tu-usuario/caetutti-dynamics.git',
      path: '/home/appuser/caetutti-dynamics',
      'pre-deploy-local': 'echo "Building locally..." && docker build -t caetutti .',
      'post-deploy': 'docker compose pull && docker compose up -d --build && docker image prune -f',
      'pre-setup': 'mkdir -p /data /var/log/caetutti',
    },
  },
};