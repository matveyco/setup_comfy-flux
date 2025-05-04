#!/usr/bin/env bash
###############################################################################
# run_comfy.sh — lightweight ComfyUI daemon launcher/replacer
# Author: ChatGPT-o3 • 2025-05-03
###############################################################################
set -Eeuo pipefail
IFS=$'\n\t'

###############################################################################
# CONFIG  (keep in-sync with install_comfy_stack.sh)
###############################################################################
AI_ROOT="/srv/ai"
COMFY_DIR="${AI_ROOT}/ComfyUI"
VENV_DIR="${COMFY_DIR}/venv"
PYTHON="${VENV_DIR}/bin/python"
COMFY_PORT=8188
LOG_FILE="${COMFY_DIR}/user/comfyui_daemon.log"
PID_FILE="${COMFY_DIR}/comfyui.pid"

export COMFYUI_MANAGER_INSTALL_DEPS=0   # never auto-upgrade wheels

###############################################################################
# HELPERS
###############################################################################
is_running() {
    [[ -f $PID_FILE ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

stop_comfy() {
    if is_running; then
        echo ">> Stopping existing ComfyUI (PID $(cat "$PID_FILE"))…"
        kill -TERM "$(cat "$PID_FILE")" 2>/dev/null || true
        # wait up to 10 s for graceful shutdown
        for i in {1..10}; do
            is_running || break
            sleep 1
        done
        is_running && { echo "!! Still alive – force killing"; kill -KILL "$(cat "$PID_FILE")"; }
        rm -f "$PID_FILE"
        echo ">> Stopped."
    fi
}

start_comfy() {
    echo ">> Launching ComfyUI as daemon on port ${COMFY_PORT}…"
    mkdir -p "$(dirname "$LOG_FILE")"
    # shellcheck source=/dev/null
    source "${VENV_DIR}/bin/activate"
    setsid "$PYTHON" "${COMFY_DIR}/main.py" \
          --listen 0.0.0.0 --port "$COMFY_PORT" \
          >>"$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo ">> New PID $(cat "$PID_FILE"). Logging to $LOG_FILE"
}

status() {
    if is_running; then
        echo "ComfyUI is **running** (PID $(cat "$PID_FILE")) – log: $LOG_FILE"
    else
        echo "ComfyUI is **not running**."
    fi
}

###############################################################################
# MAIN
###############################################################################
cmd="${1:-restart}"   # default action: restart (stop + start)
case "$cmd" in
    start)    is_running && { echo "Already running."; exit 0; }; start_comfy ;;
    stop)     stop_comfy ;;
    restart)  stop_comfy; start_comfy ;;
    status)   status ;;
    *)        echo "Usage: $0 [start|stop|restart|status]"; exit 1 ;;
esac
