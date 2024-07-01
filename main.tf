terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

data "coder_provisioner" "me" {
}

provider "docker" {
}

data "coder_workspace" "me" {
}
data "coder_workspace_owner" "me" {}


data "coder_parameter" "custom_repo_url" {
  name         = "custom_repo"
  display_name = "Repository URL"
  order        = 2
  default      = ""
  description  = "Repository URL, see [awesome-devcontainers](https://github.com/manekinekko/awesome-devcontainers)."
  mutable      = false
}

data "coder_parameter" "force_rebuild" {
  name         = "Force rebuild"
  type         = "bool"
  description  = "Rebuild the devcontainer rather than use the cached one."
  mutable      = true
  default      = false
  ephemeral    = true
}

resource "coder_agent" "main" {
  arch           = "amd64"
  os             = "linux"
  startup_script_behavior = "blocking"
  startup_script = <<EOF
  #!/bin/sh
  bash /scripts/start.sh --port 13338
  EOF

  env = {
    GIT_AUTHOR_NAME = "${data.coder_workspace_owner.me.name}"
    GIT_COMMITTER_NAME = "${data.coder_workspace_owner.me.name}"
    GIT_AUTHOR_EMAIL = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
  }
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "vscode-web"
  display_name = "VS Code Web"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13338?folder=/workspaces/code"
  subdomain    = true  # VS Code Web does currently does not work with a subpath https://github.com/microsoft/vscode/issues/192947
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13338/healthz"
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

resource "docker_container" "workspace" {
  runtime = "sysbox-runc"
  count = data.coder_workspace.me.start_count
  # Find the latest version here:
  # https://github.com/coder/envbuilder/tags
  image = "devc:latest"
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.me.name
  # Use the docker gateway if the access URL is 127.0.0.1
  # Running agent is needed for git pull hence reset of the startup items are moved to coder_agent > start.sh
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "GIT_URL=${data.coder_parameter.custom_repo_url.value}",
    "DC_ARG_REBUILD=${data.coder_parameter.force_rebuild.value ? "--remove-existing-container" : ""}",
    "INIT_SCRIPT=${replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")}"
  ]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/workspaces"
    volume_name    = docker_volume.workspaces.name
    read_only      = false
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
