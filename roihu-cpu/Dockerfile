# Docker build of the GPAW container for Roihu-CPU (x86_64, AMD Zen5).
#
# This mirrors the native Roihu build in gpaw-cpu-env (see its .gitlab-ci.yml):
#   - the package set comes from spack.yaml (copied from gpaw-cpu-env/spack.yaml),
#   - the modified recipes come from the bundled spack_repo, added with
#     `spack config add "repos:[.../spack_repo/extra]"` exactly like the GitLab CI,
#   - but instead of generate_gpaw_env.py we expose the stack through a Spack view
#     (rooted at $VIEW_DIR, generated in its own layer so it is a separate blob from the
#     install tree).
#
# The base image is pulled from CSC's public registry satama.csc.fi (no login needed).
#
# The build is split into several RUN layers for better caching. Each RUN is a fresh
# shell, so the Spack environment is re-activated at the top of every layer that needs it
# (the env state itself is persisted to disk by `spack env activate` / `spack config add`).
FROM satama.csc.fi/r_installation_spack/core-cpu-gcc-15.2.0:v2026_03

# --- OS prerequisites ---
# GPAW build kinda assumes 'which' to be available so we install it, too.
RUN dnf install -y \
        epel-release \
 && dnf install -y \
        file \
        bzip2 \
        ca-certificates \
        git \
        gzip \
        patch \
        python3 \
        tar \
        unzip \
        xz \
        zstd \
        gdb \
        which \
 && dnf clean all \
 && rm -rf /var/cache/dnf


# Where the Spack view will be created. Keep in sync with the view root in spack.yaml.
ARG VIEW_DIR=/container/gpaw
ARG ENV_DIR=/container/gpaw_env
ARG SPACK_DIR=/container/spack
ARG SPACK_PACKAGES_DIR=/container/spack-packages

# Container is rocky9 but we treat it as rhel9: lets Spack do a better job at reusing upstream packages.
# OK because these are ABI compatible.
COPY rhel9-os-release /etc/os-release

# --- Spack + builtin packages ---
# Use the same version of spack / spack-packages as in Roihu.
RUN git clone --depth 1 -b csc/v1.1 https://github.com/CSCfi/spack.git $SPACK_DIR \
 && git clone -b csc/v2026.03 --depth 1 https://github.com/CSCfi/spack-packages.git $SPACK_PACKAGES_DIR \
 && . $SPACK_DIR/share/spack/setup-env.sh \
 && spack repo add --scope site $SPACK_PACKAGES_DIR/repos/spack_repo/builtin

# Spack env setup scripts require bash.
#SHELL ["/bin/bash", "-c"]



# Spack config (package set + view) and the modified recipes, copied into the image.
RUN mkdir -p $ENV_DIR
COPY spack.yaml $ENV_DIR/spack.yaml
COPY spack_repo $ENV_DIR/spack_repo

# --- Create the environment and register the custom recipes ---
# Mimics the GitLab CI: copy spack.yaml + spack_repo into the env dir, activate it, then
# `spack config add "repos:[$PWD/spack_repo/extra]"`. The view is created in a later layer.
RUN . /opt/spack/share/spack/setup-env.sh \
 && mkdir -p "$ENV_DIR" \
 && cp /opt/gpaw_deps_config/spack.yaml "$ENV_DIR/" \
 && cp -r /opt/gpaw_deps_config/spack_repo "$ENV_DIR/" \
 && cd "$ENV_DIR" \
 && spack env activate -d "$ENV_DIR" \
 && spack config add "repos:[$PWD/spack_repo/extra]" \
 && spack repo list

# --- Concretize and install (the expensive step) ---
# spack.yaml has `view: false`, so this layer contains only the install tree (its own blob).
RUN . /opt/spack/share/spack/setup-env.sh \
 && spack env activate -d "$ENV_DIR" \
 && export LOG_DIR="$ENV_DIR/logs" \
 && mkdir -p "$LOG_DIR" \
 && spack concretize -f 2>&1 | tee "$LOG_DIR/spack-concretize.log" \
 && spack find -v --long --show-full-compiler > "$LOG_DIR/spack-concretized-specs.txt" \
 && spack find --long | tee "$LOG_DIR/spack-find.log" \
 && spack install --log-format=junit --log-file="$LOG_DIR/install.log" --show-log-on-error --fail-fast

# --- Generate the view in its own layer (separate blob from the install tree) ---
# The view is just symlinks into the install tree from the previous layer.
RUN . /opt/spack/share/spack/setup-env.sh \
 && spack env activate -d "$ENV_DIR" \
 && spack env view enable "$VIEW_DIR" \
 && spack config add "view:default:link:all" \
 && spack config add "view:default:link_type:symlink" \
 && spack env view regenerate

# --- Write the runtime environment script ---
# We want to avoid loading the spack env directly (slow!). Instead, set relevant vars to point to the spack view.
RUN ENV_SCRIPT=/opt/gpaw_deps_env.sh; \
    echo '# Activate module environment and load default modules' > $ENV_SCRIPT; \
    echo '. /opt/activate.sh' >> $ENV_SCRIPT; \
    echo "export _SPACK_GPAW_VIEW_DIR=${VIEW_DIR}" >> $ENV_SCRIPT; \
    echo "export PATH=${VIEW_DIR}/bin:\$PATH" >> $ENV_SCRIPT; \
    echo "export LIBRARY_PATH=${VIEW_DIR}/lib:${VIEW_DIR}/lib64:\$LIBRARY_PATH" >> $ENV_SCRIPT; \
    echo "export LD_LIBRARY_PATH=${VIEW_DIR}/lib:${VIEW_DIR}/lib64:\$LD_LIBRARY_PATH" >> $ENV_SCRIPT; \
    echo "export CPATH=${VIEW_DIR}/include:\$CPATH" >> $ENV_SCRIPT; \
    echo "export PKG_CONFIG_PATH=${VIEW_DIR}/lib/pkgconfig:${VIEW_DIR}/lib64/pkgconfig:\$PKG_CONFIG_PATH" >> $ENV_SCRIPT; \
    echo "export MANPATH=${VIEW_DIR}/share/man:\$MANPATH" >> $ENV_SCRIPT; \
    echo "export PYTHONPATH=${VIEW_DIR}/lib/python3.14/site-packages:\$PYTHONPATH" >> $ENV_SCRIPT

# --- Tykky setup: symlink just the executables that we'll wrap with tykky into a separate location ---
RUN TYKKY_BIN_PATTERNS="ase gpaw* python* pytest dftd3 dftd4"; \
    TYKKY_BIN_DIR=/opt/tykky_wrap/bin; \
    mkdir -p "$TYKKY_BIN_DIR"; \
    set -f; \
    for pattern in $TYKKY_BIN_PATTERNS; do \
        find "${VIEW_DIR}/bin" -maxdepth 1 -name "$pattern" | while read -r exe; do \
            ln -s "$exe" "$TYKKY_BIN_DIR"; \
        done; \
    done; \
    set +f; \
    ls "$TYKKY_BIN_DIR"

# Record build info in the image
ARG BUILD_INFO="test"
RUN printf '%b\n' "$BUILD_INFO" > /opt/build-info.txt

# Mirror the Apptainer %environment + %runscript via an entrypoint wrapper.
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh
ENTRYPOINT ["/opt/entrypoint.sh"]
CMD ["/bin/bash"]
