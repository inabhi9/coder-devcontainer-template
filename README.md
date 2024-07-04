# Coder - devcontainer Template

Coder template to build and run devcontainer and make them available on MS VSCode web instance.

## Requirements

- Coder
  - Make sure access url and wildcard url is setup for custom domain. VSCode doesn't work without subdomain.
- Docker with [sysbox-runc](https://github.com/nestybox/sysbox)


## Features

- Fully supports devcontainer spec.
- Git SSH auth with Coder's built-in ssh key management.
- Docker config for authentication for private registries.
- Port forwarding supported by Coder.

## How it works

It uses `sysbox-runc` to start containers inside a container and uses `@devcontainer/cli` utility to setup dev containers.

It should work with any runtime supports container inside a container.
