#!/bin/bash
# Docker equivalent of the Apptainer %environment + %runscript blocks:
# load the GPAW/Spack environment, then exec whatever command was given
# (defaults to an interactive bash, see CMD in the Dockerfile).
. /opt/gpaw_deps_env.sh
exec "$@"
