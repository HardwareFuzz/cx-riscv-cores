#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: ./scripts/build_all.sh [options]

Options:
  --out-dir DIR         Unified output directory for final artifacts.
                        Default: $CX_OUT_DIR if set, else ./artifacts
  --log-dir DIR         Log directory (default: ./logs/<YYYYMMDD>)
  --branch-source MODE  How to resolve target branches inside each submodule.
                        Default: origin
                        - auto: prefer an existing local branch; otherwise use origin/<branch>
                        - local: require/use a local branch if it exists, else create it from origin/<branch>
                        - origin: always reset local branch to origin/<branch>
  --cores <1|2|both>    Build 1-core, 2-core, or both (default: both)
  --matrix <minimal|all>
                        Variant matrix to build (default: minimal)
                        - minimal: all non-XiangShan ISA variants after dropping plain no-FPU labels,
                                   plus XiangShan fast defaults
                        - all: build all supported ISA/preset combinations
  --isa PATTERN         Limit ISA tags to build. May be specified multiple times.
                        Supports shell globs (quote if needed), e.g. --isa 'rv32*'
  --only a,b,c          Only build selected cores (comma-separated, case-insensitive).
                        Supported: picorv32,kronos,ibex,vexriscv,cva6,rocket-chip,boom,xiangshan,openc906,openc910
  --skip-xiangshan      Skip XiangShan (default: build)
  --with-xiangshan      (legacy) Include XiangShan (default: build)
  --xiangshan-preset <default|aligned|unaligned|both|all>
                        XiangShan preset selection (default: auto from --matrix)
                        - default: legacy alias of unaligned
                        - aligned: disable hardware misaligned load/store
                        - unaligned: explicit unaligned build label
                        - both: aligned + unaligned
                        - all: legacy alias of both
  --clean               Forward --clean to sub-build scripts
  --coverage            Forward --coverage to sub-build scripts
  --coverage-light      Forward --coverage-light to sub-build scripts
  --no-coverage         Forward --no-coverage to sub-build scripts (default)
  --dry-run             Print commands without executing
  --help, -h            Show this help

Notes:
  - This repo uses git submodules under ./cores/.
  - Each core repo is expected to provide a compatible ./build.sh.
  - Intermediate build dirs stay inside each submodule repo; only final binaries
    are copied into <out-dir> with unified names.
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

OUT_DIR_OPT=""
LOG_DIR_OPT=""
BRANCH_SOURCE="${CX_BRANCH_SOURCE:-origin}" # auto|local|origin
CORES_MODE="both" # 1|2|both
MATRIX_MODE="minimal" # minimal|all
ISA_FILTERS=()
ONLY_LIST=""
WITH_XIANGSHAN=1
XIANGSHAN_PRESET_MODE="auto" # auto|default|aligned|unaligned|both|all
CLEAN=0
COV_MODE="none" # none|full|light
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      [[ $# -ge 2 ]] || die "--out-dir requires a value"
      OUT_DIR_OPT="$2"; shift 2 ;;
    --out-dir=*)
      OUT_DIR_OPT="${1#*=}"; shift ;;
    --log-dir)
      [[ $# -ge 2 ]] || die "--log-dir requires a value"
      LOG_DIR_OPT="$2"; shift 2 ;;
    --cores)
      [[ $# -ge 2 ]] || die "--cores requires a value"
      CORES_MODE="$2"; shift 2 ;;
    --cores=*)
      CORES_MODE="${1#*=}"; shift ;;
    --branch-source)
      [[ $# -ge 2 ]] || die "--branch-source requires a value"
      BRANCH_SOURCE="${2,,}"; shift 2 ;;
    --branch-source=*)
      BRANCH_SOURCE="${1#*=}"; BRANCH_SOURCE="${BRANCH_SOURCE,,}"; shift ;;
    --only)
      [[ $# -ge 2 ]] || die "--only requires a value"
      ONLY_LIST="$2"; shift 2 ;;
    --only=*)
      ONLY_LIST="${1#*=}"; shift ;;
    --matrix)
      [[ $# -ge 2 ]] || die "--matrix requires a value"
      MATRIX_MODE="$2"; shift 2 ;;
    --matrix=*)
      MATRIX_MODE="${1#*=}"; shift ;;
    --all)
      MATRIX_MODE="all"; shift ;;
    --isa)
      [[ $# -ge 2 ]] || die "--isa requires a value"
      IFS=',' read -r -a _tmp_isas <<<"$2"
      for _isa in "${_tmp_isas[@]}"; do
        _isa="${_isa,,}"
        _isa="${_isa//[[:space:]]/}"
        [[ -n "$_isa" ]] && ISA_FILTERS+=("$_isa")
      done
      shift 2 ;;
    --isa=*)
      _val="${1#*=}"
      IFS=',' read -r -a _tmp_isas <<<"$_val"
      for _isa in "${_tmp_isas[@]}"; do
        _isa="${_isa,,}"
        _isa="${_isa//[[:space:]]/}"
        [[ -n "$_isa" ]] && ISA_FILTERS+=("$_isa")
      done
      shift ;;
    --skip-xiangshan) WITH_XIANGSHAN=0; shift ;;
    --with-xiangshan) WITH_XIANGSHAN=1; shift ;;
    --xiangshan-preset)
      [[ $# -ge 2 ]] || die "--xiangshan-preset requires a value"
      XIANGSHAN_PRESET_MODE="${2,,}"; shift 2 ;;
    --clean) CLEAN=1; shift ;;
    --coverage) COV_MODE="full"; shift ;;
    --coverage-light) COV_MODE="light"; shift ;;
    --no-coverage) COV_MODE="none"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

case "${CORES_MODE}" in
  1|2|both) ;;
  *) die "--cores must be one of: 1, 2, both (got: ${CORES_MODE})" ;;
esac

case "${BRANCH_SOURCE}" in
  auto|local|origin) ;;
  *) die "--branch-source must be one of: auto, local, origin (got: ${BRANCH_SOURCE})" ;;
esac

case "${MATRIX_MODE}" in
  minimal|all) ;;
  *) die "--matrix must be one of: minimal, all (got: ${MATRIX_MODE})" ;;
esac

case "${XIANGSHAN_PRESET_MODE}" in
  auto|default|aligned|unaligned|both|all) ;;
  *) die "--xiangshan-preset must be one of: auto, default, aligned, unaligned, both, all (got: ${XIANGSHAN_PRESET_MODE})" ;;
esac

DATE_TAG="$(date +%Y%m%d)"
OUT_DIR_DEFAULT="${ROOT_DIR}/artifacts"
OUT_DIR="${OUT_DIR_OPT:-${CX_OUT_DIR:-${OUT_DIR_DEFAULT}}}"
LOG_DIR="${LOG_DIR_OPT:-${ROOT_DIR}/logs/${DATE_TAG}}"

mkdir -p "${OUT_DIR}" "${LOG_DIR}"

# Remove F-only providers superseded by matching FD providers. This also keeps
# stale outputs from an older matrix out of release uploads.
prune_superseded_f_artifacts() {
  local -a basenames=(
    vexriscv_rv32f_1c
    rocket-chip_rv32f_1c rocket-chip_rv32f_2c
    rocket-chip_rv64f_1c rocket-chip_rv64f_2c
    openc906_rv64f_1c
    openc910_rv64f_1c openc910_rv64f_2c
    xiangshan_rv64f_aligned_1c xiangshan_rv64f_aligned_2c
    xiangshan_rv64f_unaligned_1c xiangshan_rv64f_unaligned_2c
  )
  local base suffix
  for base in "${basenames[@]}"; do
    for suffix in "" _cov _cov_light; do
      if (( DRY_RUN )); then
        echo "+ rm -f -- ${OUT_DIR}/${base}${suffix}"
      else
        rm -f -- "${OUT_DIR}/${base}${suffix}"
      fi
    done
  done
}

prune_superseded_f_artifacts

run() {
  if (( DRY_RUN )); then
    printf '+'
    printf ' %q' "$@"
    echo
    return 0
  fi
  "$@"
}

contains_core() {
  local core="$1"
  if [[ -z "${ONLY_LIST}" ]]; then
    return 0
  fi
  # Case-insensitive comma-separated list matching.
  local only_lc="${ONLY_LIST,,}"
  only_lc="${only_lc//[[:space:]]/}"
  local core_lc="${core,,}"
  [[ ",${only_lc}," == *",${core_lc},"* ]]
}

ensure_submodule() {
  local relpath="$1"
  local repo_dir="${ROOT_DIR}/${relpath}"
  if git -C "${repo_dir}" rev-parse --git-dir >/dev/null 2>&1; then
    return 0
  fi
  run git -C "${ROOT_DIR}" submodule update --init "${relpath}"
}

checkout_branch() {
  local repo_dir="$1"
  local branch="$2"

  local has_local=0
  local has_remote=0
  if git -C "${repo_dir}" rev-parse --verify --quiet "refs/heads/${branch}" >/dev/null; then
    has_local=1
  fi

  case "${BRANCH_SOURCE}" in
    auto)
      if (( has_local )); then
        run git -C "${repo_dir}" checkout -q "${branch}"
      else
        run git -C "${repo_dir}" fetch origin --prune
        if git -C "${repo_dir}" rev-parse --verify --quiet "refs/remotes/origin/${branch}" >/dev/null; then
          has_remote=1
        fi
        if (( has_remote )); then
          run git -C "${repo_dir}" checkout -q -B "${branch}" "origin/${branch}"
        else
          die "${repo_dir}: missing branch '${branch}' locally and on origin"
        fi
      fi
      ;;
    local)
      if (( has_local )); then
        run git -C "${repo_dir}" checkout -q "${branch}"
      else
        run git -C "${repo_dir}" fetch origin --prune
        if git -C "${repo_dir}" rev-parse --verify --quiet "refs/remotes/origin/${branch}" >/dev/null; then
          has_remote=1
        fi
        if (( has_remote )); then
          run git -C "${repo_dir}" checkout -q -B "${branch}" "origin/${branch}"
        else
          die "${repo_dir}: missing branch '${branch}' locally and on origin"
        fi
      fi
      ;;
    origin)
      run git -C "${repo_dir}" fetch origin --prune
      if git -C "${repo_dir}" rev-parse --verify --quiet "refs/remotes/origin/${branch}" >/dev/null; then
        has_remote=1
      fi
      (( has_remote )) || die "${repo_dir}: missing origin/${branch}"
      run git -C "${repo_dir}" checkout -q -B "${branch}" "origin/${branch}"
      ;;
  esac
}

cov_suffix() {
  case "${COV_MODE}" in
    none) echo "" ;;
    full) echo "_cov" ;;
    light) echo "_cov_light" ;;
    *) die "internal: unknown coverage mode ${COV_MODE}" ;;
  esac
}

log_tag_from_args() {
  local -a args=("$@")
  local -a isas=()
  local preset=""
  local cores=""

  for ((i=0; i<${#args[@]}; i++)); do
    case "${args[$i]}" in
      --isa)
        if (( i + 1 < ${#args[@]} )); then
          isas+=("${args[$((i+1))],,}")
          ((i++))
        fi
        ;;
      --preset)
        if (( i + 1 < ${#args[@]} )); then
          preset="${args[$((i+1))],,}"
          ((i++))
        fi
        ;;
      --cores)
        if (( i + 1 < ${#args[@]} )); then
          cores="${args[$((i+1))]}"
          ((i++))
        fi
        ;;
    esac
  done

  local tag=""
  if [[ -n "${cores}" ]]; then
    tag+="cores-${cores}"
  fi
  if (( ${#isas[@]} > 0 )); then
    [[ -n "${tag}" ]] && tag+="_"
    tag+="isa-$(IFS=+; echo "${isas[*]}")"
  fi
  if [[ -n "${preset}" ]]; then
    [[ -n "${tag}" ]] && tag+="_"
    tag+="preset-${preset}"
  fi
  [[ -n "${tag}" ]] || tag="default"

  tag="${tag// /_}"
  tag="${tag//\//_}"
  tag="${tag//:/_}"
  echo "${tag}"
}

isa_aliases_for_core() {
  local core="$1"
  local isa="${2,,}"
  case "${core}" in
    # CVA6 treats rv64fd as an alias of rv64; accept both in filters.
    cva6)
      case "${isa}" in
        rv64) printf '%s\n' rv64 rv64fd ;;
        *) printf '%s\n' "${isa}" ;;
      esac
      ;;
    *)
      printf '%s\n' "${isa}"
      ;;
  esac
}

isa_selected() {
  local core="$1"
  local isa="$2"

  if (( ${#ISA_FILTERS[@]} == 0 )); then
    return 0
  fi

  local pattern a
  local -a _aliases=()
  mapfile -t _aliases < <(isa_aliases_for_core "${core}" "${isa}")
  for pattern in "${ISA_FILTERS[@]}"; do
    for a in "${_aliases[@]}"; do
      if [[ "${a}" == ${pattern} ]]; then
        return 0
      fi
    done
  done
  return 1
}

filter_isas() {
  local core="$1"
  shift
  local -a candidates=("$@")
  local -a out=()
  for isa in "${candidates[@]}"; do
    if isa_selected "${core}" "${isa}"; then
      out+=("${isa}")
    fi
  done
  for isa in "${out[@]}"; do
    printf '%s\n' "${isa}"
  done
}

xiangshan_presets() {
  local mode="${XIANGSHAN_PRESET_MODE}"
  if [[ "${mode}" == "auto" ]]; then
    mode="${MATRIX_MODE}"
  fi
  case "${mode}" in
    minimal|default|unaligned) printf '%s\n' unaligned ;;
    aligned) printf '%s\n' aligned ;;
    both|all) printf '%s\n' aligned unaligned ;;
    *)
      die "internal: unexpected xiangshan preset mode '${mode}'"
      ;;
  esac
}

build_in_repo() {
  local name="$1"
  local branch="$2"
  shift 2
  local repo_dir="${ROOT_DIR}/cores/${name}"

  ensure_submodule "cores/${name}"
  checkout_branch "${repo_dir}" "${branch}"
  case "${name}" in
    boom)
      # Chipyard/BOOM ships a targeted submodule bootstrap script. A blind
      # recursive update pulls optional trees such as Ara's llvm-project,
      # which is unnecessary for the BOOM simulator builds we publish here.
      run bash -lc "cd '${repo_dir}' && ./scripts/init-submodules-no-riscv-tools-nolog.sh"
      ;;
    *)
      run git -C "${repo_dir}" submodule update --init --recursive
      ;;
  esac

  local build_cmd=("./build.sh")
  build_cmd+=("$@")
  build_cmd+=("--out-dir" "${OUT_DIR}")

  if (( CLEAN )); then
    build_cmd+=("--clean")
  fi

  case "${COV_MODE}" in
    none) build_cmd+=("--no-coverage") ;;
    full) build_cmd+=("--coverage") ;;
    light) build_cmd+=("--coverage-light") ;;
    *) die "internal: unknown coverage mode ${COV_MODE}" ;;
  esac

  local log_tag
  log_tag="$(log_tag_from_args "$@")"
  local log_file="${LOG_DIR}/${name}_${branch}_${log_tag}.log"
  echo "[build] ${name} (${branch}) ${log_tag} -> ${OUT_DIR}"

  if (( DRY_RUN )); then
    echo "+ (cd ${repo_dir} && CX_OUT_DIR=${OUT_DIR} ${build_cmd[*]}) | tee ${log_file}"
    return 0
  fi

  (
    cd "${repo_dir}"
    export CX_OUT_DIR="${OUT_DIR}"
    "${build_cmd[@]}" 2>&1 | tee "${log_file}"
  )
}

build_picorv32() {
  local branch="$1"
  local cores="$2"
  local -a candidates=(rv32)
  mapfile -t candidates < <(filter_isas picorv32 "${candidates[@]}")
  if (( ${#candidates[@]} == 0 )); then
    echo "[skip] picorv32: no ISA matches --isa filter"
    return 0
  fi
  build_in_repo picorv32 "${branch}" --isa "${candidates[0]}" --cores "${cores}"
}

build_kronos() {
  local branch="$1"
  local cores="$2"
  local -a candidates=(rv32)
  mapfile -t candidates < <(filter_isas kronos "${candidates[@]}")
  if (( ${#candidates[@]} == 0 )); then
    echo "[skip] kronos: no ISA matches --isa filter"
    return 0
  fi
  build_in_repo kronos "${branch}" --isa "${candidates[0]}" --cores "${cores}"
}

build_ibex() {
  local branch="$1"
  local cores="$2"
  local -a candidates=(rv32imc)
  mapfile -t candidates < <(filter_isas ibex "${candidates[@]}")
  if (( ${#candidates[@]} == 0 )); then
    echo "[skip] ibex: no ISA matches --isa filter"
    return 0
  fi
  build_in_repo ibex "${branch}" --isa "${candidates[0]}" --cores "${cores}"
}

build_vexriscv() {
  local branch="$1"
  local cores="$2"
  local -a candidates=(rv32fd)

  mapfile -t candidates < <(filter_isas VexRiscv "${candidates[@]}")
  if (( ${#candidates[@]} == 0 )); then
    echo "[skip] VexRiscv: no ISA matches --isa filter"
    return 0
  fi
  for isa in "${candidates[@]}"; do
    build_in_repo VexRiscv "${branch}" --isa "${isa}" --cores "${cores}"
  done
}

build_cva6() {
  local branch="$1"
  local cores="$2"
  local -a candidates=(rv64fd rv32f)
  local cov_suf
  cov_suf="$(cov_suffix)"

  mapfile -t candidates < <(filter_isas cva6 "${candidates[@]}")
  if (( ${#candidates[@]} == 0 )); then
    echo "[skip] cva6: no ISA matches --isa filter"
    return 0
  fi

  if (( CLEAN )); then
    for isa in "${candidates[@]}"; do
      case "${isa}" in
        rv64fd)
          run rm -f \
            "${OUT_DIR}/cva6_rv64fd_${cores}c${cov_suf}" \
            "${OUT_DIR}/cva6_rv64_${cores}c${cov_suf}"
          ;;
        rv32f)
          run rm -f \
            "${OUT_DIR}/cva6_rv32f_${cores}c${cov_suf}" \
            "${OUT_DIR}/cva6_rv32_${cores}c${cov_suf}"
          ;;
      esac
    done
  fi

  local -a args=()
  for isa in "${candidates[@]}"; do
    args+=(--isa "${isa}")
  done
  args+=(--cores "${cores}")
  build_in_repo cva6 "${branch}" "${args[@]}"

  for isa in "${candidates[@]}"; do
    local src=""
    local dst=""
    case "${isa}" in
      rv64fd)
        dst="${OUT_DIR}/cva6_rv64fd_${cores}c${cov_suf}"
        if [[ -e "${OUT_DIR}/cva6_rv64fd_${cores}c${cov_suf}" ]]; then
          src="${OUT_DIR}/cva6_rv64fd_${cores}c${cov_suf}"
        elif [[ -e "${OUT_DIR}/cva6_rv64_${cores}c${cov_suf}" ]]; then
          src="${OUT_DIR}/cva6_rv64_${cores}c${cov_suf}"
        else
          die "cva6 build did not produce an rv64fd artifact for ${cores}c"
        fi
        ;;
      rv32f)
        dst="${OUT_DIR}/cva6_rv32f_${cores}c${cov_suf}"
        if [[ -e "${OUT_DIR}/cva6_rv32f_${cores}c${cov_suf}" ]]; then
          src="${OUT_DIR}/cva6_rv32f_${cores}c${cov_suf}"
        elif [[ -e "${OUT_DIR}/cva6_rv32_${cores}c${cov_suf}" ]]; then
          src="${OUT_DIR}/cva6_rv32_${cores}c${cov_suf}"
        else
          die "cva6 build did not produce an rv32f artifact for ${cores}c"
        fi
        ;;
      *)
        die "internal: unexpected cva6 isa '${isa}'"
        ;;
    esac

    if [[ "${src}" != "${dst}" ]]; then
      if (( DRY_RUN )); then
        echo "+ mv -f ${src} ${dst}"
      else
        mv -f "${src}" "${dst}"
      fi
    fi
  done
}

build_rocket_chip() {
  local branch="$1"
  local cores="$2"
  local -a candidates=(rv64fd rv32fd)

  mapfile -t candidates < <(filter_isas rocket-chip "${candidates[@]}")
  if (( ${#candidates[@]} == 0 )); then
    echo "[skip] rocket-chip: no ISA matches --isa filter"
    return 0
  fi

  local -a args=()
  for isa in "${candidates[@]}"; do
    args+=(--isa "${isa}")
  done
  args+=(--cores "${cores}")
  build_in_repo rocket-chip "${branch}" "${args[@]}"
}

build_boom() {
  local _branch="$1"
  local cores="$2"
  local -a candidates=(rv64fd)

  mapfile -t candidates < <(filter_isas boom "${candidates[@]}")
  if (( ${#candidates[@]} == 0 )); then
    echo "[skip] boom: no ISA matches --isa filter"
    return 0
  fi

  local -a args=()
  for isa in "${candidates[@]}"; do
    args+=(--isa "${isa}")
  done
  args+=(--cores "${cores}")
  build_in_repo boom "cx-build" "${args[@]}"
}

build_openc906() {
  local branch="$1"
  local cores="$2"
  local -a candidates=(rv64fd)

  if [[ "${cores}" != "1" ]]; then
    echo "[skip] openc906: only 1-core RV64 artifacts are supported"
    return 0
  fi

  mapfile -t candidates < <(filter_isas openc906 "${candidates[@]}")
  if (( ${#candidates[@]} == 0 )); then
    echo "[skip] openc906: no ISA matches --isa filter"
    return 0
  fi

  local -a args=()
  for isa in "${candidates[@]}"; do
    args+=(--isa "${isa}")
  done
  args+=(--cores "${cores}")
  build_in_repo openc906 "${branch}" "${args[@]}"
}

build_openc910() {
  local branch="$1"
  local cores="$2"
  local -a candidates=(rv64fd)

  if [[ "${cores}" != "1" && "${cores}" != "2" ]]; then
    echo "[skip] openc910: only 1- and 2-core RV64 artifacts are supported"
    return 0
  fi

  mapfile -t candidates < <(filter_isas openc910 "${candidates[@]}")
  if (( ${#candidates[@]} == 0 )); then
    echo "[skip] openc910: no ISA matches --isa filter"
    return 0
  fi

  local -a args=()
  for isa in "${candidates[@]}"; do
    args+=(--isa "${isa}")
  done
  args+=(--cores "${cores}")
  build_in_repo openc910 "${branch}" "${args[@]}"
}

build_xiangshan() {
  local branch="$1"
  local cores="$2"
  local -a isas=(rv64fd)

  mapfile -t isas < <(filter_isas XiangShan "${isas[@]}")
  if (( ${#isas[@]} == 0 )); then
    echo "[skip] XiangShan: no ISA matches --isa filter"
    return 0
  fi

  local -a presets=()
  mapfile -t presets < <(xiangshan_presets)
  local cov_suf
  cov_suf="$(cov_suffix)"
  local primary_isa="${isas[0]}"

  for preset in "${presets[@]}"; do
    local -a args=(--isa "${primary_isa}" --cores "${cores}" --preset "${preset}")
    local preset_tag="_${preset}"

    if (( CLEAN )); then
      for isa in "${isas[@]}"; do
        run rm -f "${OUT_DIR}/xiangshan_${isa}${preset_tag}_${cores}c${cov_suf}"
      done
    fi

    build_in_repo XiangShan "${branch}" "${args[@]}"

  done
}

build_set() {
  local branch="$1"
  local cores="$2"

  if contains_core picorv32; then
    build_picorv32 "${branch}" "${cores}"
  fi
  if contains_core kronos; then
    build_kronos "${branch}" "${cores}"
  fi
  if contains_core ibex; then
    build_ibex "${branch}" "${cores}"
  fi
  if contains_core VexRiscv; then
    build_vexriscv "${branch}" "${cores}"
  fi
  if contains_core cva6; then
    build_cva6 "${branch}" "${cores}"
  fi
  if contains_core rocket-chip; then
    build_rocket_chip "${branch}" "${cores}"
  fi
  if contains_core boom; then
    build_boom "${branch}" "${cores}"
  fi
  if contains_core openc906; then
    build_openc906 "${branch}" "${cores}"
  fi
  if contains_core openc910; then
    build_openc910 "${branch}" "${cores}"
  fi
  if (( WITH_XIANGSHAN )); then
    if contains_core XiangShan; then
      build_xiangshan "${branch}" "${cores}"
    fi
  fi
}

stage_runtime_support() {
  local stage_script="${ROOT_DIR}/scripts/stage_runtime_support.sh"
  if (( DRY_RUN )); then
    echo "+ ${stage_script} --artifact-dir ${OUT_DIR}"
    return 0
  fi
  "${stage_script}" --artifact-dir "${OUT_DIR}"
}

echo "OUT_DIR=${OUT_DIR}"
echo "LOG_DIR=${LOG_DIR}"
echo "BRANCH_SOURCE=${BRANCH_SOURCE}"
echo "CORES=${CORES_MODE}"
echo "MATRIX=${MATRIX_MODE}"
echo "ONLY=${ONLY_LIST:-<all>}"
echo "ISA_FILTER=$([[ ${#ISA_FILTERS[@]} -gt 0 ]] && (IFS=,; echo "${ISA_FILTERS[*]}") || echo "<all>")"
echo "COVERAGE=${COV_MODE}"
echo "XIANGSHAN=$([[ ${WITH_XIANGSHAN} -eq 1 ]] && echo on || echo off)"
echo "XIANGSHAN_PRESET=${XIANGSHAN_PRESET_MODE}"
echo

if [[ "${CORES_MODE}" == "1" || "${CORES_MODE}" == "both" ]]; then
  build_set "cx-build" "1"
fi

if [[ "${CORES_MODE}" == "2" || "${CORES_MODE}" == "both" ]]; then
  build_set "cx-2hart-build" "2"
fi

stage_runtime_support

echo
echo "Artifacts:"
ls -1 "${OUT_DIR}" | sed -n '1,200p'
