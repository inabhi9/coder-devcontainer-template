#!/bin/bash

cd /workspaces
mkdir /workspaces/.vscode-cli || true
mkdir /workspaces/.docker || true

dockerd --data-root /workspaces/.docker > /var/log/docker.log 2>&1 &
sleep 2

if [ ! -d "./code" ] ; then
    git clone ${GIT_URL} ./code
fi

CONFIG_PATH=./code/.devcontainer/devcontainer.json
cp ${CONFIG_PATH} ${CONFIG_PATH}.bak
node /scripts/forward-port.js ${CONFIG_PATH}

devcontainer up ${DC_ARG_REBUILD} --workspace-folder=./code \
    --mount=type=bind,source=/tmp/code_x64,target=/usr/bin/code \
    --mount=type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
    --mount=type=bind,source=/workspaces/.vscode-cli,target=/root/.vscode

mv ${CONFIG_PATH}.bak ${CONFIG_PATH}

devcontainer exec --workspace-folder=./code code serve-web --host 0.0.0.0 $@ --without-connection-token --accept-server-license-terms > /var/log/devc-web.log 2>&1 &
