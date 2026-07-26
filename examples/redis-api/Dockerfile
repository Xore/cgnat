FROM python:3.14-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py gunicorn.conf.py ./
COPY static ./static

EXPOSE 5001

CMD ["gunicorn", "-c", "gunicorn.conf.py", "app:app"]
