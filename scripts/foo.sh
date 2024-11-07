#!/usr/bin/env bash

set -eu

name=${1-foo}

while true; do
    echo "$(date) - Hello, World! ${name}" 1>&2
    echo $foo
    sleep 1
done