#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
docker compose -f ./w0.docker-compose.yaml up  --build --force-recreate --remove-orphans