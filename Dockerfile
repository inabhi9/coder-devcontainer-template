FROM codercom/enterprise-node:ubuntu

RUN curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' -o /tmp/vscode_cli.tar.gz \
    && tar -xf /tmp/vscode_cli.tar.gz -C /tmp \
    && mv /tmp/code /tmp/code_x64 \
    && rm -fr /tmp/vscode_cli.tar.gz

RUN sudo npm install -g @devcontainers/cli json5 yaml

ENV NODE_PATH=/usr/lib/node_modules

COPY start.sh /scripts/start.sh

RUN mkdir -p ~/.ssh && printf "Host *\n\tStrictHostKeyChecking no\n" > ~/.ssh/config
