FROM node:22-bookworm-slim

RUN apt update && apt install -y curl \
    && rm -rf /var/lib/apt/lists/* 

RUN curl -fsSL https://get.docker.com -o get-docker.sh \
    && sh get-docker.sh

RUN curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' -o /tmp/vscode_cli.tar.gz \
    && tar -xf /tmp/vscode_cli.tar.gz -C /tmp \
    && mv /tmp/code /tmp/code_x64 \
    && rm -fr /tmp/vscode_cli.tar.gz

RUN npm install -g @devcontainers/cli json5

ENV NODE_PATH=/usr/local/lib/node_modules

RUN printf "Host *\n\tStrictHostKeyChecking no\n" > ~/.ssh/config
COPY start.sh /scripts/start.sh
COPY forward-port.js /scripts/forward-port.js

RUN mkdir /workspaces
