terraform {
  required_providers {
    coder = {
      source = "coder/coder"
      version = ">=2.4.0"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

data "coder_provisioner" "me" {
}


data "coder_workspace" "me" {
}

data "coder_workspace_owner" "me" {}

locals {
  coder_app_subdomain = true
  coder_app_slug = "vscode-web"
  vscode_server_base_path = local.coder_app_subdomain ? "" : "/@${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}/apps/${local.coder_app_slug}/"
  vscode_server_args = "--server-data-dir /host/vscode-server --user-data-dir /host/vscode-user-data --server-base-path '${local.vscode_server_base_path}'"
  devcontainer_flag_rebuid = data.coder_parameter.force_rebuild.value ? "--remove-existing-container" : ""
  # git module has a bug that appens / infront of folder name if doesn't exist.
  project_dir = replace(module.git_clone_source.folder_name, "/^~/", "$HOME")
  devcontainer_poststart_script = join("\\n", [
    "ln -fs /host/vscode-server ~/.vscode",
    "ln -fs /host/vscode-server ~/.vscode-server",
    "ln -fs /host/ssh ~/.ssh",
    "chown |dlr|(whoami) -R ~/.ssh"
  ]) 
}

variable "docker_config" {
  type        = string
  description = "Docker config. Typically contains registry credential and other information"
  default     = ""
  sensitive   = true
}

variable "docker_socket" {
  default     = ""
  description = "Docker socket URI"
  type        = string
}


provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
  disable_docker_daemon_check = true
}

data "coder_parameter" "custom_repo_url" {
  name         = "custom_repo"
  display_name = "Git Repository URL"
  order        = 2
  description  = "Git Repository URL, see [awesome-devcontainers](https://github.com/manekinekko/awesome-devcontainers)."
  mutable      = false
}

data "coder_parameter" "devcontainer_repo_url" {
  name         = "devcontainer_repo"
  display_name = "Devcontainer repository URL"
  order        = 2
  default      = ""
  description  = "A separate repository to locate .devcontainer directory. When provided, it's cloned to temporary directory and provided during devcontainer build."
  mutable      = true
}

data "coder_parameter" "force_rebuild" {
  name         = "Force rebuild"
  type         = "bool"
  description  = "Rebuild the devcontainer rather than use the cached one."
  mutable      = true
  default      = false
  ephemeral    = true
}

module "git_clone_source" {
  source   = "registry.coder.com/coder/git-clone/coder"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.custom_repo_url.value
  base_dir = "~"
  # This ensures that the latest non-breaking version of the module gets
  # downloaded, you can also pin the module version to prevent breaking
  # changes in production.
  version = "~> 1.0"
}

module "git_clone_devcontainer" {
  version = "~> 1.0"
  count    = data.coder_parameter.devcontainer_repo_url.value == "" ? 0 : 1
  source   = "registry.coder.com/coder/git-clone/coder"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.devcontainer_repo_url.value
  base_dir = "~"
  post_clone_script = <<EOF
  #!/bin/sh
  cp -r ${module.git_clone_devcontainer[0].repo_dir}/.devcontainer ${module.git_clone_source.repo_dir}
  git -C ${module.git_clone_source.repo_dir} config --replace-all core.excludesFile ${module.git_clone_source.repo_dir}/.git/.exclude
  echo .devcontainer > ${module.git_clone_source.repo_dir}/.git/info/exclude
  rm -fr ${module.git_clone_devcontainer[0].repo_dir}
  EOF
}

module "devcontainers_cli" {
  source   = "registry.coder.com/coder/devcontainers-cli/coder"
  version  = "1.0.32"
  agent_id = coder_agent.main.id
}

resource "coder_agent" "main" {
  arch           = "amd64"
  os             = "linux"
  startup_script_behavior = "blocking"
  startup_script = <<EOF
  #!/bin/sh
  set -e

  sudo service docker start

  git config --global user.name "${data.coder_workspace_owner.me.name}"
  git config --global user.email "${data.coder_workspace_owner.me.email}"

  mkdir -p ~/.ssh $HOME/.devcontainer/repo ~/.ssh
  
  echo "access_path: ${local.vscode_server_base_path}"

  printf "Host *\n\tStrictHostKeyChecking no\n" > ~/.ssh/config
  curl -s -H "Coder-Session-Token: $CODER_AGENT_TOKEN" $${CODER_AGENT_URL}api/v2/workspaceagents/me/gitsshkey \
    | jq -r '.private_key' > ~/.ssh/id_ed25519 \
    && chmod 600 $HOME/.ssh/id_ed25519

  while ! devcontainer --version > /dev/null || pgrep git > /dev/null || ! docker info > /dev/null
  do
      echo "Waiting for everything to be ready..."
      sleep 2
  done

  devcontainer up ${local.devcontainer_flag_rebuid} --workspace-folder=${local.project_dir} \
    --mount=type=bind,source=$HOME/.devcontainer,target=/host \
    --mount=type=bind,source=$HOME/.ssh,target=/host/ssh \
    --mount=type=bind,source=$HOME/.gitconfig,target=/etc/gitconfig \
    --additional-features='{"ghcr.io/inabhi9/devcontainer-features/msvscode-server:1.0.5": {"vscodeServerFlags": "${local.vscode_server_args}", "postContainerStartCommand": "${local.devcontainer_poststart_script}"}}' | tee $HOME/.devcontainer/result.json

  EOF

  env = {
    GIT_AUTHOR_NAME = "${data.coder_workspace_owner.me.name}"
    GIT_COMMITTER_NAME = "${data.coder_workspace_owner.me.name}"
    GIT_AUTHOR_EMAIL = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
  }

  display_apps {
    vscode          = false
    vscode_insiders = false
    web_terminal    = true
    ssh_helper      = false
    port_forwarding_helper = false
  }
}


resource "coder_app" "code_server" {
  agent_id     = coder_agent.main.id
  slug         = local.coder_app_slug
  display_name = "VS Code Web"
  icon         = "/icon/code.svg"
  url          = "http://127.0.0.1:13338${local.vscode_server_base_path}?folder=/workspaces/${module.git_clone_source.folder_name}"
  subdomain    = local.coder_app_subdomain
  share        = "owner"

  healthcheck {
    url       = "http://127.0.0.1:13338/healthz"
    interval  = 2
    threshold = 100
  }

}

resource "docker_volume" "workspaces" {
  name = "coder-${data.coder_workspace.me.id}"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_volume" "docker_data_root" {
  name = "coder-docker-data-${data.coder_workspace.me.id}"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_container" "workspace" {
  runtime = "sysbox-runc"
  
  count = data.coder_workspace.me.start_count
  # Find the latest version here:
  # https://github.com/coder/envbuilder/tags
  image = "codercom/enterprise-node:ubuntu"
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.me.name
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "GIT_URL=${data.coder_parameter.custom_repo_url.value}",
    "INIT_SCRIPT=${replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")}",
    "DOCKER_CONFIG_JSON=${var.docker_config}"
  ]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.workspaces.name
    read_only      = false
  }
  volumes {
    container_path = "/var/lib/docker"
    volume_name    = docker_volume.docker_data_root.name
    read_only      = false
  }

  capabilities {
    # --cap-add=NET_ADMIN and --cap-add=NET_RAW are needed for iptables
    # to forward vscode server port
    add = ["NET_RAW", "NET_ADMIN"]
  }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
