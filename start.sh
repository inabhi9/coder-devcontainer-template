#!/bin/bash

mkdir -p /workspaces/.vscode-cli /workspaces/.docker ~/.ssh ~/.logs
sudo mkdir -p /root/.docker

# Found this api when these CODER_AGENT_* env vars are not set and executing `./coder gitssh --`
curl -s -H "Coder-Session-Token: $CODER_AGENT_TOKEN" ${CODER_AGENT_URL}api/v2/workspaceagents/me/gitsshkey \
    | jq -r '.private_key' > ~/.ssh/id_ed25519 \
    && chmod 600 $HOME/.ssh/id_ed25519

sudo sh -c "echo $DOCKER_CONFIG_JSON > /root/.docker/config.json"
sudo dockerd --data-root /workspaces/.docker > ~/.logs/dockerd.log 2>&1 &
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
    --mount=type=bind,source=/workspaces/.vscode-cli,target=/workspaces/.vscode-cli \
    --mount=type=bind,source=$HOME/.ssh/id_ed25519,target=/tmp/.ssh/id_ed25519

mv ${CONFIG_PATH}.bak ${CONFIG_PATH}

devcontainer exec --workspace-folder=./code bash -c 'ln -fs /workspaces/.vscode-cli $HOME/ && ln -fs /tmp/.ssh $HOME/ && chown $(whomai) -R ~/.ssh'
devcontainer exec --workspace-folder=./code code serve-web --host 0.0.0.0 $@ --without-connection-token --accept-server-license-terms > ~/.logs/vscode-web.log 2>&1 &
