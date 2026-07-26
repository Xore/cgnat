FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py gunicorn.conf.py ./
COPY static ./static

EXPOSE 5000

# Run via gunicorn config file
CMD ["gunicorn", "-c", "gunicorn.conf.py", "app:app"]
