import multiprocessing

bind = "0.0.0.0:5001"
backlog = 2048
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "sync"
timeout = 30
keepalive = 5
graceful_timeout = 30
accesslog = "-"
errorlog = "-"
loglevel = "info"
proc_name = "redis-api"
