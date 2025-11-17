#!/bin/bash

sudo apt install -y socat

mkdir -p $HOME/.vscode $HOME/.docker/data ~/.ssh ~/.logs

# Found this api when these CODER_AGENT_* env vars are not set and executing `./coder gitssh --`
curl -s -H "Coder-Session-Token: $CODER_AGENT_TOKEN" ${CODER_AGENT_URL}api/v2/workspaceagents/me/gitsshkey \
    | jq -r '.private_key' > ~/.ssh/id_ed25519 \
    && chmod 600 $HOME/.ssh/id_ed25519

echo $DOCKER_CONFIG_JSON > $HOME/.docker/config.json
sudo dockerd --data-root $HOME/.docker/data > ~/.logs/dockerd.log 2>&1 &
sleep 2

if [ ! -d "$HOME/code" ] ; then
     clone ${GIT_URL} $HOME/code
fi

DEVC_CONF=/tmp/devcontainer_repo/.devcontainer/devcontainer.json
DEVC_CONF_OVERRIDE=$(if [ -f $DEVC_CONF ]; then echo "--override-config $DEVC_CONF"; fi)
DEVC_OUTPUT=$(devcontainer up ${DC_ARG_REBUILD} $DEVC_CONF_OVERRIDE --workspace-folder=$HOME/code \
    --mount=type=bind,source=/tmp/code_x64,target=/usr/bin/code \
    --mount=type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
    --mount=type=bind,source=$HOME/.vscode,target=/workspaces/.vscode \
    --mount=type=bind,source=$HOME/.ssh,target=/tmp/.ssh \
    --mount=type=bind,source=$HOME/.gitconfig,target=/etc/gitconfig)

sleep 1
echo $DEVC_OUTPUT

# Proxy to the vscode
CONTAINER_ID=$(echo $DEVC_OUTPUT | jq -r .containerId)
echo 'container id'
echo $CONTAINER_ID
CONTAINER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_ID)
nohup socat TCP-LISTEN:13338,fork,reuseaddr TCP:$CONTAINER_IP:13338 > /dev/null 2>&1 &
echo "Devcontainer up successful"

devcontainer exec --workspace-folder=$HOME/code bash -c 'ln -fs /workspaces/.vscode $HOME/ && ln -fs /tmp/.ssh $HOME/'
devcontainer exec --workspace-folder=$HOME/code bash -c 'chown $(whoami) -R $HOME/.ssh'
devcontainer exec --workspace-folder=$HOME/code code serve-web --host 0.0.0.0 $@ --server-data-dir /workspaces/.vscode/server --without-connection-token --accept-server-license-terms > ~/.logs/vscode-web.log 2>&1 &
