# Debian GPU Node Bootstrap

Use this runbook to bring a newly provisioned Debian workstation or server into the HomeOps GPU-worker fleet without committing environment-specific details to git.

## Goal

Prepare a Debian node to host one or more local AI workloads such as:

- `llm-service`
- `local-tts-service`
- other CUDA-backed container or Python services

This runbook assumes:

- Debian is already installed
- data storage is mounted and writable
- the node is reachable over SSH
- Docker is present or will be installed during bootstrap

## 1. Baseline OS Checks

Confirm the node has a usable operator account with `sudo` access.

Install baseline admin packages if missing:

```bash
sudo apt update
sudo apt install -y \
  sudo \
  curl \
  wget \
  git \
  jq \
  tmux \
  vim \
  htop \
  btop \
  tree \
  ripgrep \
  fd-find \
  unzip \
  zip \
  rsync \
  ffmpeg \
  pciutils \
  python3-venv
```

If Docker is not present, install and verify it before continuing.

## 2. Data Layout

Create stable host directories for models, runtime state, and service checkouts.

Generic example:

```bash
mkdir -p \
  /data/docker \
  /data/models \
  /data/llm \
  /data/projects \
  /data/backups
```

Ensure the operator account owns the writable data roots:

```bash
sudo chown -R <user>:<group> /data
```

## 3. GPU Detection

Confirm the GPU is visible on PCI before installing drivers:

```bash
lspci | grep -Ei 'vga|3d|nvidia|display'
```

If the card is not visible here, stop and fix firmware, BIOS, or hardware issues first.

## 4. NVIDIA Driver And Container Runtime

For CUDA-backed containers, the host must provide:

- NVIDIA kernel driver
- `nvidia-smi`
- NVIDIA container toolkit for Docker

Verify current state:

```bash
command -v nvidia-smi
docker info
```

If `nvidia-smi` is missing but the GPU appears in `lspci`, install the appropriate NVIDIA driver and reboot.

After the driver is working, install the NVIDIA container runtime and verify container access to the GPU:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

Do not proceed with `llm-service` until this check passes.

### 4a. Legacy / Pascal GPUs (GTX 10xx, Tesla P-series, etc.)

NVIDIA's `cuda-drivers` and `cuda-drivers-<branch>` meta-packages on the
official `developer.download.nvidia.com/compute/cuda/repos/debian12` repo
depend on **unversioned** sub-packages (`nvidia-driver`, `nvidia-driver-cuda`,
`nvidia-kernel-dkms`, …). Without an apt pin, those resolve to the newest
branch in the repo, which on current Debian 13 is **595.x — and 595 has
dropped support for Pascal and earlier**. The driver loads, but `dmesg`
shows `NVRM: ... is supported through the NVIDIA 580.xx Legacy drivers.
The 595.xx NVIDIA driver will ignore this GPU.` and `nvidia-smi` fails with
"couldn't communicate with the NVIDIA driver".

Required recipe for Pascal (compute capability 6.x) and older:

```bash
# 1. Install the apt pinning file FIRST. This drops a Priority=1000 pin
#    that forces every nvidia-* sub-dep to stay on the 580 branch.
sudo apt-get install -y nvidia-driver-pinning-580

# 2. Install dkms + kernel headers so the kernel module can build.
sudo apt-get install -y dkms linux-headers-amd64

# 3. Now install the branch meta-package and the container toolkit.
sudo apt-get install -y cuda-drivers-580 nvidia-container-toolkit

# 4. If sub-packages were already installed at the wrong version
#    (e.g. 595.x left over from a previous attempt), force them down:
sudo apt-get install --allow-downgrades -y \
  nvidia-driver=580.159.04-1 nvidia-driver-cuda=580.159.04-1 \
  nvidia-kernel-dkms=580.159.04-1 libcuda1:amd64=580.159.04-1 \
  firmware-nvidia-gsp=580.159.04-1
  # (extend list to cover every libnvidia-* / nvidia-* dpkg shows at 595)

# 5. Verify DKMS built the module against the running kernel:
dkms status   # expect:  nvidia/580.159.04, <running-kernel>, x86_64: installed

# 6. Reboot, then confirm.
sudo systemctl reboot
nvidia-smi    # must show the 580.x driver and the GPU
docker run --rm --gpus all nvidia/cuda:12.9.1-base-ubuntu24.04 nvidia-smi
```

If a previous install already pulled the 595 branch, you must purge it
before step 1 or the pin file alone will not downgrade existing packages:

```bash
sudo apt-get purge -y 'cuda-drivers' 'nvidia-driver' 'nvidia-kernel-dkms' \
  'cuda-drivers-fabricmanager' 'libnvidia-*' 'nvidia-*'
sudo apt-get autoremove -y
# Note: this also removes nvidia-container-toolkit — reinstall it in step 3
# and re-run `sudo nvidia-ctk runtime configure --runtime=docker` followed
# by `sudo systemctl restart docker`.
```

Pascal-specific llama.cpp build flag:

When building a CUDA llama.cpp image for a Pascal GPU, the binary must
include the `sm_61` compute capability or it will fail at model load with
no kernel available for the device. In the `llm-service-core` stack this is
controlled via the `.env`:

```bash
LLAMA_CUDA_ARCHITECTURES=61
```

After changing it, rebuild without cache:

```bash
docker compose build --no-cache && docker compose up -d
```

## 5. `llm-service` Readiness

`llm-service` expects persistent model and state directories.

Host paths commonly needed:

- `/data/models`
- `/data/llm`

The repo-level `.env` should be adjusted for the node’s actual storage layout before deployment.

Minimum checks:

```bash
test -d /data/models
test -d /data/llm || mkdir -p /data/llm
```

Before placing the node into rotation:

1. choose the intended model size for that node
2. place or download the target GGUF file into the model directory
3. set a unique host port if multiple LLM nodes will be reached from the same management surface
4. set a non-empty `ADMIN_TOKEN`

Smoke test:

```bash
curl http://<node-or-bind-address>:<llm-port>/health
curl http://<node-or-bind-address>:<llm-port>/api/node
```

## 6. `local-tts-service` Readiness

`local-tts-service` currently fits best as a host-local Python service rather than a managed blue/green app.

Recommended host prerequisites:

- Python 3.11
- `ffmpeg`
- CUDA-capable Torch environment if GPU inference is desired

Create a dedicated virtual environment instead of relying on the system interpreter:

```bash
python3.11 -m venv .venv311
source .venv311/bin/activate
pip install -r requirements.txt
```

Smoke tests:

```bash
python -m apps.api.run
curl http://localhost:5000/health
curl http://localhost:5000/runtime
```

If the node only has Python 3.13 installed, treat Python 3.11 setup as a prerequisite task before restoring the TTS service.

## 7. Service Supervision

For long-running host services, add explicit supervision instead of relying on an interactive shell.

Use one of:

- `systemd` unit for Python-backed services
- Docker restart policies for container workloads

At minimum, define:

- working directory
- environment file path
- log destination
- restart policy
- health check endpoint

## 8. Final Verification

Before marking the node ready:

1. reboot once after GPU driver and storage changes
2. verify Docker starts automatically
3. verify `nvidia-smi` works after reboot
4. verify all intended data mounts are present
5. verify each service health endpoint responds

## 9. Inventory Update

After bootstrap:

1. update local `.inventory/nodes.yaml`
2. update `.inventory/services.yaml`
3. update `.inventory/repos.yaml` if deployment ownership changed
4. pack and upload the encrypted inventory bundle
