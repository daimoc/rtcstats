# docker build -t rtcstats-server --target rtcstats-server -f Dockerfile .
# docker build -t rtcstats-features --target rtcstats-features -f Dockerfile .
# docker run -p 8080:8080 rtcstats-server
# Configuration can be passed via environment variables, e.g.
# docker run -p 8080:8071 -e NODE_CONFIG='{"server": {"httpPort":8071}}' rtcstats-server
# The features worker needs the same database and storage config as the server:
# docker run -e NODE_CONFIG='{"database": {...}, "storage": {...}}' rtcstats-features
FROM node:22-alpine AS base

# tini as PID 1 so SIGTERM reaches node and `docker stop` shuts down promptly.
RUN apk add --no-cache tini

WORKDIR /server

COPY package.json ./
COPY packages/rtcstats-shared/package.json packages/rtcstats-shared/
COPY packages/rtcstats-node-shared/package.json packages/rtcstats-node-shared/

# Default config only; deploy-time config is injected via NODE_CONFIG or a mount.
COPY config/default.yaml config/default.yaml
ENV NODE_CONFIG_DIR=/server/config
ENTRYPOINT ["/sbin/tini", "--"]

# Feature extraction worker. No HTTP port, it polls the database for new dumps.
FROM base AS rtcstats-features

COPY packages/rtcstats-features/package.json packages/rtcstats-features/

RUN npm install --omit=dev \
    --workspace=packages/rtcstats-features \
    --include-workspace-root

COPY packages/rtcstats-shared packages/rtcstats-shared
COPY packages/rtcstats-node-shared packages/rtcstats-node-shared
COPY packages/rtcstats-features packages/rtcstats-features

RUN chown -R node:node /server
USER node

WORKDIR /server/packages/rtcstats-features
CMD ["node", "app.js"]

# Server. Kept as the last stage so a plain `docker build .` still builds it.
FROM base AS rtcstats-server

COPY packages/rtcstats-server/package.json packages/rtcstats-server/

RUN npm install --omit=dev \
    --workspace=packages/rtcstats-server \
    --include-workspace-root

COPY packages/rtcstats-shared packages/rtcstats-shared
COPY packages/rtcstats-node-shared packages/rtcstats-node-shared
COPY packages/rtcstats-server packages/rtcstats-server

RUN chown -R node:node /server
USER node

EXPOSE 8080
WORKDIR /server/packages/rtcstats-server
HEALTHCHECK --interval=30s --timeout=3s \
    CMD wget -qO- http://localhost:8080/healthcheck || exit 1
CMD ["node", "app.js"]
