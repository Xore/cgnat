# Gunicorn configuration file
# https://docs.gunicorn.org/en/stable/settings.html
#
# WARNING: Do NOT use multiprocessing.cpu_count() here.
# Inside Docker the container sees all host CPUs, but the memory limit
# is set per-container. On a 4-core host this spawns 9 workers which
# easily exceeds the 256M limit and causes SIGKILL loops.
#
# Rule: set workers based on your memory limit, not CPU count.
#   Each sync worker uses ~30-60MB. With 256M limit: 2 workers is safe.
#   Increase memory limit in docker-compose.yml if you need more workers.

# Server socket
bind = "0.0.0.0:5000"
backlog = 512

# Worker processes
workers = 1                 # blog stores posts in a JSON flat file — one worker
                            # keeps read-modify-write cycles consistent
worker_class = "sync"       # use 'gevent' for IO-heavy / many concurrent requests
threads = 1
worker_connections = 1000
timeout = 30
keepalive = 5
graceful_timeout = 30

# Logging
accesslog = "-"
errorlog = "-"
loglevel = "info"
access_log_format = '%(h)s "%(r)s" %(s)s %(b)s %(D)sus'

# Process naming
proc_name = "python-api"

# Security
limit_request_line = 4096
limit_request_fields = 100
limit_request_field_size = 8190
