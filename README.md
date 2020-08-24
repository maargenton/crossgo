# crossgo

Container-based cross-compiler package for CGo projects and their native
dependencies

[![Build](
https://img.shields.io/github/workflow/status/maargenton/crossgo/ci)](
https://github.com/maargenton/crossgo/actions)
[![Release](
https://img.shields.io/github/v/release/maargenton/crossgo)](
https://github.com/maargenton/crossgo/releases/latest)

## Overview

**crossgo** has two main components: a container image containing all the
necessary build tools, and a shell script that run both outside and inside the
container and bridges the two environments.

The `crossgo` command, when run from the host environment, captures the relevant
environment variables (`GOOS` and `GOARCH`) and jumps into the container to run
the desired build command. The current working directory on the host is mounted
inside the container under `/workdir`, and used as the initial working directory
within the container.

When no further arguments are provided to `crossgo`, the command drops into an
interactive bash shell running inside the container; otherwise, all the
arguments are concatenated and passed as a `-c` argument to the nested shell.

If both `GOOS` and `GOARCH` are specified, a cross-compilation toolchain is
configured for the corresponding target; otherwise the default environment is
used.

If `CROSSGO_IMAGE` is defined, the image specified is used to run the
containerized side of crossgo, instead of the default image. If `CROSSGO_IMAGE`
is defined with the special value `.`, a new image is built from the the
current folder Dockerfile, and used instead of the default image.

The C/C++ cross-compiler toolchain support is based on
[multiarch/crossbuild](https://github.com/multiarch/crossbuild). Refer to their
documentation for supported platform and details.

## Install

Docker is required to run `crossgo`. The docker daemon must be able to mount
local volumes, which in most cases means that it has to be a locally running
daemon.


```sh
wget https://github.com/maargenton/crossgo/releases/download/v1.0.0/crossgo-v1.0.0.tar.gz
tar -C /usr/local -xf crossgo-v1.0.0.tgz
```

For development installation:
```sh
git clone https://github.com/maargenton/crossgo.git
cd crossgo
GOOS=darwin GOARCH=amd64 rake
```

## Usage

Building a go binary for a specific target
```sh
GOOS=darwin GOARCH=amd64 crossgo go build ./...
```

Running with local-built image:
```sh
CROSSGO_IMAGE=. GOOS=darwin GOARCH=amd64 crossgo go build ./...
```

## License

MIT
