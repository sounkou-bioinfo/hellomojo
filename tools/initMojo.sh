#!/bin/env bash
# install mojo and pixi if necessary
set -e
pixi="${HOME}/.pixi/bin/pixi"
thisDir=$(dirname "$0")
command -v $pixi >/dev/null 2>&1 || { 
    echo "pixi not found, installing pixi..." >&2; 
    curl -fsSL https://pixi.sh/install.sh | sh
}
if [ ! -f "$pixi" ]; then
    echo "pixi installation failed!" >&2
    exit 1
fi
cd ${thisDir}/../inst/mojo || mkdir -p ${thisDir}/../inst/mojo
cd ${thisDir}/../inst/mojo
$pixi init hellomojo -c https://conda.modular.com/max-nightly/ -c conda-forge || true
cd hellomojo || exit 1
$pixi add "mojo==0.25.6" || true
$pixi run mojo --version
# add macos platform
$pixi add  --platform osx-arm64 clang
$pixi add --platform linux-aarch64 gcc
#$pixi run mojo hello.mojo
$pixi run mojo build hello.mojo  --emit shared-lib -o hello.so
ls hello.so
# load this in R via dyn.load("path/to/hello.so") and call the function hello()
Rscript -e 'dyn.load("hello.so"); is.loaded("hello"); .C("hello")'