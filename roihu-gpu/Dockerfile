# Docker build of the GPAW container for Roihu-GPU (aarch64, NVIDIA Grace + Hopper).
# This is the Dockerfile equivalent of gpaw_gpu_base.def + gpaw_gpu_pip.def (Apptainer),
# combined into a single build. Build it on an aarch64 host; the resulting image targets
# the Neoverse V2 microarchitecture and sm_90a GPUs.
#
# The base image is pulled from CSC's public registry satama.csc.fi (no login needed).
#
# This recipe has a lot in common with roihu-cpu/Dockerfile. See there for detailed comments.
# The %post steps are split into several RUN layers for better build caching. Each RUN is a
# fresh shell, so the Spack environment is re-activated at the top of every layer that needs it.
FROM satama.csc.fi/r_installation_spack/core-gpu-gcc-15.2.0-cuda-13.1.1:v2026_03

# Spack env setup scripts require bash.
SHELL ["/bin/bash", "-c"]

# Where the Spack view will be created. Keep in sync with config/spack.yaml.
ARG VIEW_DIR=/opt/gpaw_container
ENV VIEW_DIR=${VIEW_DIR}

COPY config/rhel9-os-release /etc/os-release
COPY config/spack.yaml /opt/gpaw_deps_config/spack.yaml
COPY config/gpaw_gpu_siteconfig.py /opt/gpaw_deps_config/siteconfig.py

# --- OS prerequisites ---
RUN set -exo pipefail \
 && mkdir -p /users \
 && dnf install --assumeyes epel-release \
 && dnf install --assumeyes file bzip2 ca-certificates git gzip patch python3 tar unzip xz zstd gdb which

# --- Spack + spack-packages setup ---
# Use the same version of spack / spack-packages as on Roihu. We also add the upstream
# spack-packages remote and fetch develop so we can grab individual up-to-date recipes below.
RUN set -exo pipefail \
 && cd /opt \
 && git clone --depth 1 -b csc/v1.1 https://github.com/CSCfi/spack.git \
 && . spack/share/spack/setup-env.sh \
 && upstream=g15cu131_eg \
 && spack env create /opt/environments/gpaw_deps /opt/gpaw_deps_config/spack.yaml \
 && spack env activate /opt/environments/gpaw_deps \
 && spack config add upstreams:${upstream}:install_tree:/appl/soft/spack/core/v2026_03/aarch64/${upstream}/install_dir \
 && spack config add config:source_cache:source-cache \
 && git clone -b csc/v2026.03 --depth 1 https://github.com/CSCfi/spack-packages.git \
 && spack repo add spack-packages/repos/spack_repo/builtin \
 && cd spack-packages \
 && git remote add upstream https://github.com/spack/spack-packages.git \
 && git fetch upstream develop --depth=1 \
 && spack external find pkgconf pkg-config

# --- Package specs ---
# Add packages, fetching newest recipes from the upstream spack-packages repo when needed. Notes:
# - GPU-aware libxc is currently supported only in GPAW dev version, so we install the CPU-only
#   version for now. For the next GPAW release, swap in the GPU variant:
#       spack add libxc@7.1.2+fhc+cuda cuda_arch=90a ~fortran
# - python is pulled in with tkinter (^tk+xft+xss).
# - py-pytest pinned to 9.0: GPAW tests have a bug incompatible with pytest >=9.1 (fixed in newer GPAW).
# - ASE provides wrappers for dftd3/dftd4 but doesn't install them for you, so add them explicitly.
# - elpa@2025.06.001 was bad, so we fetch newer recipes. https://gitlab.com/gpaw/gpaw/-/merge_requests/3226
# - CuPy, ASE and GPAW itself are installed with pip further below (tricky to get via Spack).
RUN set -exo pipefail \
 && . /opt/spack/share/spack/setup-env.sh \
 && spack env activate /opt/environments/gpaw_deps \
 && cd /opt/spack-packages \
 && git checkout upstream/develop -- repos/spack_repo/builtin/packages/libxc \
 && spack add libxc@7.1.2+fhc ~fortran \
 && spack add libvdwxc@0.5.0+mpi \
 && spack add python@3.14 ^tk+xft+xss \
 && spack add py-numpy@2.4 \
 && spack add py-scipy@1.17 \
 && spack add py-pytest@9.0 \
 && spack add dftd3-lib@0.10 \
 && spack add dftd4@3.7.0 ^python@3.14 \
 && git checkout upstream/develop -- repos/spack_repo/builtin/packages/elpa \
 && spack add elpa@2026.02.002 +mpi

# --- Concretize and install (the expensive step) ---
RUN set -exo pipefail \
 && . /opt/spack/share/spack/setup-env.sh \
 && spack env activate /opt/environments/gpaw_deps \
 && export LOG_DIR=/opt/environments/gpaw_deps/logs \
 && mkdir -p $LOG_DIR \
 && spack concretize -f 2>&1 | tee $LOG_DIR/spack-concretize.log \
 && spack find -v --long --show-full-compiler > $LOG_DIR/spack-concretized-specs.txt \
 && spack find --long | tee $LOG_DIR/spack-find.log \
 && spack install --log-format=junit --log-file=$LOG_DIR/install.log --show-log-on-error --fail-fast

# --- Write the runtime environment script ---
# We want to avoid loading the spack env directly (slow!). Instead, set relevant vars to point to the spack view.
# This must happen before the pip step below, which sources it to build GPAW against the Spack-installed libs.
RUN set -ex; \
    ENV_SCRIPT=/opt/gpaw_deps_env.sh; \
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

# --- pip packages: safety patch, CuPy, ASE and GPAW (was gpaw_gpu_pip.def) ---
# pip/certifi safety patch for compromised eMudhra certificates:
# https://discuss.python.org/t/information-for-python-users-regarding-emudhra-emsign-ca-certificate-security-incident/109576
# Should end up with pip >= 26.2.2, certifi >= 2026.10.19. Then CuPy, pybind11, ASE and finally GPAW
# (built with --no-build-isolation against the Spack libs, using our siteconfig).
RUN set -exo pipefail \
 && . /opt/gpaw_deps_env.sh \
 && cd /opt \
 && python -m ensurepip \
 && python -m pip install "pip @ https://files.pythonhosted.org/packages/3f/06/3e4420302363fbb71be3c7f35ce042f54bfca330e3e66b3a2e3c4cca579f/pip-26.2.2-py3-none-any.whl#sha256=fd7f4dfa8190e014013b9f08f3e973f4e4c26ffd179a204895533a7254813a70" \
 && python -m pip install --upgrade certifi \
 && python -m pip --version \
 && python -m pip list | grep certifi \
 && python -m pip install setuptools packaging --upgrade \
 && python -m pip install cupy-cuda13x==14.1.1 \
 && python -m pip install pybind11==3.0.1 \
 && python -m pip install ase==3.29.0 \
 && git clone --depth=1 --branch 26.7.0 https://gitlab.com/gpaw/gpaw.git \
 && export GPAW_CONFIG=/opt/gpaw_deps_config/siteconfig.py \
 && cd gpaw \
 && python -m pip install -v . --no-build-isolation \
 && cd .. \
 && rm -rf /opt/gpaw

# --- Tykky setup: symlink just the executables that we'll wrap with tykky into a separate location ---
RUN set -ex; \
    TYKKY_BIN_PATTERNS="ase gpaw* python* pytest dftd3 dftd4"; \
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

# Record build info in the image (passed from CI as a build-arg; \n sequences expanded by printf %b).
ARG BUILD_INFO
RUN printf '%b\n' "$BUILD_INFO" > /opt/build-info.txt

# Mirror the Apptainer %environment + %runscript via an entrypoint wrapper.
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh
ENTRYPOINT ["/opt/entrypoint.sh"]
CMD ["/bin/bash"]
