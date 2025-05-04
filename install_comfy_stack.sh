#!/usr/bin/env bash
###############################################################################
# install_comfy_stack.sh • bullet-proof ComfyUI stack (Ubuntu 22.04 LTS)
###############################################################################
set -Eeuo pipefail
IFS=$'\n\t'
###############################################################################
# 0. ---- SETTINGS ------------------------------------------------------------
###############################################################################
AI_ROOT="/srv/ai"                  # where everything lives
COMFY_DIR="${AI_ROOT}/ComfyUI"
VENV_DIR="${COMFY_DIR}/venv"
PYTHON_EXE="/usr/bin/python3"
COMFY_PORT=8188                    # change if needed

CUDA_TAG="cu124"                   # choose cu118 / cu121 / cu124 / cu126
TORCH_VER="2.5.1+${CUDA_TAG}"
TORCHVISION_VER="0.20.1+${CUDA_TAG}"
TORCHAUDIO_VER="2.5.1+${CUDA_TAG}"
PIP_EXTRA_INDEX="https://download.pytorch.org/whl/${CUDA_TAG}"

# Wheels EVERY node eventually needs
BASE_EXTRA_WHEELS=(
  opencv-python-headless==4.10.0.82
  safetensors
  diffusers==0.27.2
  accelerate
  compel
  huggingface_hub==0.22.2
)

# Pin NumPy stack so Mediapipe & Numba stay happy
PINNED_WHEELS=(
  numpy==1.26.4
  numba==0.59.0
  llvmlite==0.42.0
  mediapipe==0.10.21
)

# Public custom-node repos (all 200-OK, no auth)
CUSTOM_NODE_REPOS=(
  "https://github.com/ltdrdata/ComfyUI-Manager.git"
  "https://github.com/Fannovel16/comfyui_controlnet_aux.git"
  "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
  "https://github.com/WASasquatch/was-node-suite-comfyui.git"
)
###############################################################################
# 1. ---- HELPERS --------------------------------------------------------------
###############################################################################
msg(){ printf "\e[1;32m>> %s\e[0m\n" "$*"; }
die(){ printf "\e[1;31m!! %s\e[0m\n" "$*" >&2; exit 1; }
ensure_root(){ [[ $EUID -eq 0 ]] || die "Run with sudo/root."; }

check_repo(){ git ls-remote -h "$1" &>/dev/null || die "Bad repo URL $1"; }

clone_or_update(){
  local url=$1 dest=$2
  if [[ -d $dest/.git ]]; then git -C "$dest" pull --ff-only
  else git clone --depth 1 "$url" "$dest"
  fi
}

stop_running_comfy(){
  if pgrep -f "${COMFY_DIR}/main.py" &>/dev/null; then
    msg "Stopping existing ComfyUI…"; pkill -f "${COMFY_DIR}/main.py"; sleep 3
  fi
}

install_node_deps(){
  local d=$1
  [[ -f $d/install.py ]] && python "$d/install.py" || true
  for req in "$d"/requirements*.txt; do [[ -f $req ]] && pip install -U -r "$req"; done
  [[ -f $d/install.py ]] && python "$d/install.py" || true
}
###############################################################################
# 2. ---- SYSTEM DEPS ----------------------------------------------------------
###############################################################################
install_sys_deps(){
  msg "Installing system packages via apt…"
  apt update -qq
  DEBIAN_FRONTEND=noninteractive apt install -y \
      git build-essential aria2 wget ffmpeg libgl1 libglib2.0-0 \
      python3 python3-venv python3-pip python-is-python3 \
      nvidia-cuda-toolkit nvidia-modprobe
}

setup_dirs(){ mkdir -p "$AI_ROOT"; chown -R "$(logname):$(logname)" "$AI_ROOT"; }
###############################################################################
# 3. ---- PYTHON VENV + COMFYUI CORE ------------------------------------------
###############################################################################
install_comfy(){
  clone_or_update "https://github.com/comfyanonymous/ComfyUI.git" "$COMFY_DIR"

  [[ -e $VENV_DIR/bin/activate ]] || $PYTHON_EXE -m venv "$VENV_DIR"
  # shellcheck source=/dev/null
  source "$VENV_DIR/bin/activate"

  pip install -U pip wheel

  msg "Installing PyTorch stack (${TORCH_VER})…"
  pip install --extra-index-url "$PIP_EXTRA_INDEX" \
      torch=="$TORCH_VER" torchvision=="$TORCHVISION_VER" torchaudio=="$TORCHAUDIO_VER"

  msg "Installing ComfyUI requirements + pinned wheels…"
  pip install -U -r "${COMFY_DIR}/requirements.txt"
  pip install -U "${PINNED_WHEELS[@]}" "${BASE_EXTRA_WHEELS[@]}"

  deactivate
}
###############################################################################
# 4. ---- CUSTOM NODES ---------------------------------------------------------
###############################################################################
install_custom_nodes(){
  mkdir -p "$COMFY_DIR/custom_nodes"
  # shellcheck source=/dev/null
  source "$VENV_DIR/bin/activate"
  for repo in "${CUSTOM_NODE_REPOS[@]}"; do
    check_repo "$repo"
    name=$(basename -s .git "$repo")
    dest="$COMFY_DIR/custom_nodes/$name"
    clone_or_update "$repo" "$dest"
    install_node_deps "$dest"
  done
  deactivate
}
###############################################################################
# 5. ---- LAUNCH ---------------------------------------------------------------
###############################################################################
launch_comfy(){
  stop_running_comfy
  export COMFYUI_MANAGER_INSTALL_DEPS=0   # block silent wheel upgrades
  # shellcheck source=/dev/null
  source "$VENV_DIR/bin/activate"
  cd "$COMFY_DIR"
  msg "ComfyUI running →  http://<server-ip>:${COMFY_PORT}"
  python main.py --listen 0.0.0.0 --port "$COMFY_PORT"
}
###############################################################################
# MAIN ------------------------------------------------------------------------
###############################################################################
ensure_root
install_sys_deps
setup_dirs
install_comfy
install_custom_nodes
msg "✅  Install complete.  Drop checkpoints into ${COMFY_DIR}/models/* and restart."
launch_comfy
