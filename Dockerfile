# syntax=docker/dockerfile:1

# ============================================================
# Base
# ============================================================
FROM oven/bun:1.4.2 AS base

WORKDIR /app


# ============================================================
# Dependencies
# ============================================================
FROM base AS deps

WORKDIR /app

COPY package.json bun.lock ./

COPY bun-patches ./bun-patches

COPY packages/ui/package.json ./packages/ui/
COPY packages/web/package.json ./packages/web/
COPY packages/electron/package.json ./packages/electron/
COPY packages/vscode/package.json ./packages/vscode/
COPY packages/mobile/package.json ./packages/mobile/
COPY packages/sdk/package.json ./packages/sdk/

RUN bun install --frozen-lockfile --ignore-scripts


# ============================================================
# Builder
# ============================================================
FROM deps AS builder

WORKDIR /app

COPY . .

# The server imports @openchamber/sdk at runtime.
# Dependencies were installed with --ignore-scripts, so the
# root postinstall did not build the SDK.
# Build it explicitly before building the web application.
RUN bun run --cwd packages/sdk build

WORKDIR /app/packages/web

RUN bun run build


# ============================================================
# Runtime
# ============================================================
FROM oven/bun:1.4.2 AS runtime

WORKDIR /home/openchamber


# ============================================================
# System packages
# ============================================================
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  bash \
  ca-certificates \
  git \
  less \
  nodejs \
  npm \
  openssh-client \
  python3 \
  && rm -rf /var/lib/apt/lists/*


# ============================================================
# Create openchamber user
# ============================================================
#
# The oven/bun image already contains /home/openchamber.
#
# IMPORTANT:
# Do NOT use `useradd -m` here.
#
# `-m` tells useradd to create the home directory and copy
# files from /etc/skel. Since /home/openchamber already exists,
# useradd produces:
#
#   useradd: warning: the home directory /home/openchamber already exists.
#   useradd: Not copying any file from skel directory into it.
#
# We explicitly configure the existing directory instead.
#
RUN userdel bun \
  && groupadd -g 1000 openchamber \
  && useradd \
  -M \
  -u 1000 \
  -g 1000 \
  -d /home/openchamber \
  -s /bin/bash \
  openchamber \
  && mkdir -p /home/openchamber \
  && chown -R openchamber:openchamber /home/openchamber


# ============================================================
# Run as openchamber
# ============================================================
USER openchamber


# ============================================================
# NPM / Node global configuration
# ============================================================
ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=/home/openchamber/.npm-global/bin:${PATH}


# ============================================================
# Create user directories and install OpenCode CLI
# ============================================================
RUN mkdir -p \
  /home/openchamber/.npm-global \
  /home/openchamber/.local \
  /home/openchamber/.config \
  /home/openchamber/.ssh \
  && npm config set prefix /home/openchamber/.npm-global \
  && npm install -g @opencode/cli@2.0.22


# ============================================================
# Cloudflare Tunnel
# ============================================================
# cloudflared 2026.3.0
# Update the digest explicitly when upgrading cloudflared.
COPY --from=cloudflare/cloudflared@sha256:6d91c121b803126f7a5344005d17a9324788fc09d305b6e2560ec6040a7ae283 \
  /usr/local/bin/cloudflared \
  /usr/local/bin/cloudflared


# ============================================================
# Environment
# ============================================================
ENV NODE_ENV=production

# Use UTF-8 locale so bash/readline handles Khmer and other
# multibyte characters correctly.
ENV LANG=C.UTF-8


# ============================================================
# Entrypoint
# ============================================================
COPY --chown=openchamber:openchamber \
  scripts/docker-entrypoint.sh \
  /home/openchamber/openchamber-entrypoint.sh


# ============================================================
# Application dependencies
# ============================================================
COPY --from=builder \
  /app/node_modules \
  ./node_modules

COPY --from=builder \
  /app/packages/web/node_modules \
  ./packages/web/node_modules


# ============================================================
# Package manifests
# ============================================================
COPY --from=builder \
  /app/package.json \
  ./package.json

COPY --from=builder \
  /app/packages/web/package.json \
  ./packages/web/package.json

COPY --from=builder \
  /app/packages/sdk/package.json \
  ./packages/sdk/package.json


# ============================================================
# SDK build output
# ============================================================
COPY --from=builder \
  /app/packages/sdk/dist \
  ./packages/sdk/dist


# ============================================================
# Web application
# ============================================================
COPY --from=builder \
  /app/packages/web/bin \
  ./packages/web/bin

COPY --from=builder \
  /app/packages/web/server \
  ./packages/web/server

COPY --from=builder \
  /app/packages/web/dist \
  ./packages/web/dist


# ============================================================
# Port
# ============================================================
EXPOSE 3000


# ============================================================
# Start application
# ============================================================
ENTRYPOINT ["sh", "/home/openchamber/openchamber-entrypoint.sh"]
