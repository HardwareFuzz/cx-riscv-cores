#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${CX_OUT_DIR:-${ROOT_DIR}/artifacts}"

usage() {
  cat <<'EOF'
Usage: ./scripts/generate_env.sh [--artifact-dir DIR]

Emit sh-compatible exports for cx-riscv-cores runtime assets. Env names follow
the artifact basenames:

  <artifact basename> -> CX_RISCV_CORES_<UPPER_SNAKE_BASENAME>

Examples:
  cva6_rv32f_1c             -> CX_RISCV_CORES_CVA6_RV32F_1C
  rocket-chip_rv64fd_2c     -> CX_RISCV_CORES_ROCKET_CHIP_RV64FD_2C
  xiangshan_difftest_rv64_1c_so -> CX_RISCV_CORES_XIANGSHAN_DIFFTEST_RV64_1C_SO
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --artifact-dir requires a value" >&2; exit 1; }
      ARTIFACT_DIR="$2"
      shift 2
      ;;
    --artifact-dir=*)
      ARTIFACT_DIR="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

[[ -d "${ARTIFACT_DIR}" ]] || {
  echo "ERROR: artifact directory does not exist: ${ARTIFACT_DIR}" >&2
  exit 1
}

"${ROOT_DIR}/scripts/stage_runtime_support.sh" --artifact-dir "${ARTIFACT_DIR}" >/dev/null

emit_export() {
  local name="$1"
  local value="$2"
  printf 'export %s=%q\n' "${name}" "${value}"
}

artifact_env_name() {
  local name="$1"
  name="${name^^}"
  name="${name//-/_}"
  name="${name//./_}"
  printf 'CX_RISCV_CORES_%s\n' "${name}"
}

emit_export "CX_RISCV_CORES_ROOT" "${ROOT_DIR}"
emit_export "CX_RISCV_CORES_ARTIFACT_DIR" "${ARTIFACT_DIR}"

mapfile -d '' artifact_paths < <(find "${ARTIFACT_DIR}" -maxdepth 1 -type f ! -name '*.json' -print0 | sort -z)

for path in "${artifact_paths[@]}"; do
  [[ -n "${path}" ]] || continue
  base="$(basename "${path}")"
  emit_export "$(artifact_env_name "${base}")" "${path}"
done

if [[ ! -f "${ARTIFACT_DIR}/spike" ]]; then
  spike_path="$(command -v spike || true)"
  if [[ -n "${spike_path}" ]]; then
    emit_export "CX_RISCV_CORES_SPIKE" "${spike_path}"
  else
    echo "[warn] spike not found in PATH; CX_RISCV_CORES_SPIKE was not emitted" >&2
  fi
fi
