FROM n8nio/runners:2.13.4

USER root

RUN ARCH=$(uname -m) && \
    wget -qO- "http://dl-cdn.alpinelinux.org/alpine/latest-stable/main/${ARCH}/" | \
    grep -o 'href="apk-tools-static-[^"]*\.apk"' | head -1 | cut -d'"' -f2 | \
    xargs -I {} wget -q "http://dl-cdn.alpinelinux.org/alpine/latest-stable/main/${ARCH}/{}" && \
    tar -xzf apk-tools-static-*.apk && \
    ./sbin/apk.static -X http://dl-cdn.alpinelinux.org/alpine/latest-stable/main \
        -U --allow-untrusted add apk-tools && \
    rm -rf sbin apk-tools-static-*.apk

# Install python3, pip, and build deps
RUN apk add --no-cache \
      python3 \
      py3-pip \
      py3-virtualenv \
      build-base \
      git \
      bash \
      jq \
      ca-certificates

RUN mkdir -p /init && chown -R root:root /init

# Custom entrypoint wrapper
COPY <<'ENTRYPOINT_SH' /docker-entrypoint.sh
#!/usr/bin/env bash
set -euo pipefail

echo "[init] Checking for /init/requirements.txt and /init/package.json..."

if [ "${SKIP_PACKAGE_INSTALLATION:-false}" != "true" ]; then
  if [ -f /init/requirements.txt ]; then
    echo "[init] Installing Python dependencies..."
    uv pip install -r /init/requirements.txt || {
      echo "[init][error] pip install failed"; exit 1;
    }
  else
    echo "[init] No Python requirements found."
  fi

  # Cannot be done at the moment since not npm not pnpm are available at this point of code
  # if [ -f /init/package.json ]; then
  #   echo "[init] Installing global npm packages from /init..."
  #   npm install -g /init --unsafe-perm --no-audit --no-fund || {
  #     echo "[init][warning] npm install failed, retrying with custom prefix..."
  #     PREFIX_DIR="/root/.npm-global"
  #     mkdir -p "${PREFIX_DIR}"
  #     npm config set prefix "${PREFIX_DIR}"
  #     export PATH="${PREFIX_DIR}/bin:${PATH}"
  #     npm install -g /init --unsafe-perm --no-audit --no-fund || {
  #       echo "[init][error] npm install failed completely"
  #     }
  #   }
  # else
  #   echo "[init] No package.json found."
  # fi
fi

echo "[init] Starting n8n task runners..."
exec tini -- /usr/local/bin/task-runner-launcher "$@"
ENTRYPOINT_SH

# Patch JSON to allow more env vars
RUN jq '.["task-runners"][0]["allowed-env"] |= (. + ["NODE_FUNCTION_ALLOW_BUILTIN","NODE_FUNCTION_ALLOW_EXTERNAL"] | unique) | .["task-runners"][1]["allowed-env"] |= (. + ["N8N_RUNNERS_STDLIB_ALLOW","N8N_RUNNERS_EXTERNAL_ALLOW"] | unique)' \
    /etc/n8n-task-runners.json > /tmp/tmp.json && \
    mv /tmp/tmp.json /etc/n8n-task-runners.json

RUN jq '.["task-runners"][0]["env-overrides"] += {"NODE_FUNCTION_ALLOW_BUILTIN":"*","NODE_FUNCTION_ALLOW_EXTERNAL":"*"} | .["task-runners"][1]["env-overrides"] += {"N8N_RUNNERS_STDLIB_ALLOW":"*","N8N_RUNNERS_EXTERNAL_ALLOW":"*"}' \
    /etc/n8n-task-runners.json > /tmp/tmp.json && \
    mv /tmp/tmp.json /etc/n8n-task-runners.json


# Ensure Python virtualenv in PATH
ENV VIRTUAL_ENV=/opt/runners/task-runner-python/.venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN chmod +x /docker-entrypoint.sh
RUN chown runner:runner -R /opt/runners/task-runner-python/* /opt/runners/task-runner-python/.*

USER runner

EXPOSE 5678

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["javascript", "python"]
