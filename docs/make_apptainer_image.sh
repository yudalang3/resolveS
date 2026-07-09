#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/../.." &> /dev/null && pwd )"

cd "$PROJECT_ROOT"
bash make_apptainer_image.sh
