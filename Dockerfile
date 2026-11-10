# NextStep API + Flutter web build.
# Build the web app first (scripts/build_web.sh) so app_flutter/build/web exists;
# without it the API still runs and /app/ explains how to build it.
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /srv
RUN useradd --create-home --uid 10001 nextstep
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
COPY content ./content
COPY config ./config
COPY data/services.csv data/README.md ./data/
COPY scripts ./scripts
COPY app_flutter/build/web* ./app_flutter/build/web/
RUN mkdir -p /srv/data && chown -R nextstep /srv/data
USER nextstep
EXPOSE 8077
HEALTHCHECK --interval=30s --timeout=5s CMD python -c "import os,urllib.request;urllib.request.urlopen('http://127.0.0.1:'+os.environ.get('PORT','8077')+'/healthz')" || exit 1
CMD ["sh", "scripts/start.sh"]
