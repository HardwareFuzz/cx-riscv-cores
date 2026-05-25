#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${ROOT_DIR}/artifacts"

usage() {
  cat <<'EOF'
Usage: ./scripts/stage_runtime_support.sh [--artifact-dir DIR]

Copy runtime support files into the unified artifact directory so consumers
only need one root: <artifact-dir>/.
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

mkdir -p "${ARTIFACT_DIR}"

stage_one() {
  local src="$1"
  local dst_name="$2"
  local mode="${3:-data}"
  if [[ ! -f "${src}" ]]; then
    echo "[warn] missing runtime support file: ${src}" >&2
    return 0
  fi

  local dst="${ARTIFACT_DIR}/${dst_name}"
  cp -f "${src}" "${dst}"
  if [[ "${mode}" == "executable" ]]; then
    chmod 0755 "${dst}"
  fi
  echo "[stage] ${dst_name} <- ${src}"
}

XIANGSHAN_READY_TO_RUN="${ROOT_DIR}/cores/XiangShan/ready-to-run"
stage_one "${XIANGSHAN_READY_TO_RUN}/riscv64-nemu-interpreter-so" "xiangshan_difftest_rv64_1c_so"
stage_one "${XIANGSHAN_READY_TO_RUN}/riscv64-nemu-interpreter-dual-so" "xiangshan_difftest_rv64_2c_so"

BOOM_DRAMSIM_DIR="${ROOT_DIR}/cores/boom/generators/testchipip/src/main/resources/dramsim2_ini"
stage_one "${BOOM_DRAMSIM_DIR}/system.ini" "boom_dramsim2_system.ini"
stage_one "${BOOM_DRAMSIM_DIR}/DDR3_micron_64M_8B_x4_sg15.ini" "boom_dramsim2_DDR3_micron_64M_8B_x4_sg15.ini"

stage_one "${ROOT_DIR}/cores/openc906/smart_run/tests/bin/Srec2vmem" "openc_srec2vmem" "executable"
