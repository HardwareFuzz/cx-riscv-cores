#!/usr/bin/env bash
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI is required. Install https://cli.github.com/ and authenticate first." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${CX_OUT_DIR:-${ROOT_DIR}/artifacts}"
SAFE_UPLOAD_SCRIPT="${ROOT_DIR}/scripts/upload_release_asset_safe.sh"

if [[ ! -d "${ARTIFACT_DIR}" ]]; then
  echo "Error: artifact directory does not exist: ${ARTIFACT_DIR}" >&2
  exit 1
fi

if [[ ! -x "${SAFE_UPLOAD_SCRIPT}" ]]; then
  echo "Error: safe upload helper is missing or not executable: ${SAFE_UPLOAD_SCRIPT}" >&2
  exit 1
fi

"${ROOT_DIR}/scripts/stage_runtime_support.sh" --artifact-dir "${ARTIFACT_DIR}"

python_cmd=${PYTHON_BIN:-$(command -v python3 || command -v python || true)}
if [[ -z "${python_cmd}" ]]; then
  echo "Error: python3 (or python) is required for checksum manifest management." >&2
  exit 1
fi

release_tag=${CX_RISCV_CORES_RELEASE_TAG:-"dev-release"}
release_title=${CX_RISCV_CORES_RELEASE_TITLE:-"cx-riscv-cores runtime artifacts"}
release_notes=${CX_RISCV_CORES_RELEASE_NOTES:-"Unified cx-riscv-cores artifacts and runtime support files."}
manifest_name=${CX_RISCV_CORES_RELEASE_MANIFEST:-"cx_riscv_cores_artifacts_manifest.json"}

if ! gh release view "${release_tag}" >/dev/null 2>&1; then
  gh release create "${release_tag}" \
    --title "${release_title}" \
    --notes "${release_notes}" \
    --prerelease
fi

declare -a artifacts=()
while IFS= read -r -d '' file; do
  artifacts+=("${file}")
done < <(find "${ARTIFACT_DIR}" -maxdepth 1 -type f ! -name '*.json' -print0 | sort -z)

if [[ "${#artifacts[@]}" -eq 0 ]]; then
  echo "Error: No artifact files found under ${ARTIFACT_DIR}." >&2
  exit 1
fi

tmp_dir=$(mktemp -d)
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

updates_json="${tmp_dir}/updates.json"
"${python_cmd}" - <<'PY' "${updates_json}" "${artifacts[@]}"
import hashlib
import json
import os
import sys

output_path = sys.argv[1]
paths = sys.argv[2:]
data = {}
for path in paths:
    name = os.path.basename(path)
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            if not chunk:
                break
            h.update(chunk)
    data[name] = h.hexdigest()
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY

assets_json="${tmp_dir}/assets.json"
gh release view "${release_tag}" --json assets > "${assets_json}"

manifest_path="${tmp_dir}/${manifest_name}"
manifest_present=$("${python_cmd}" - <<'PY' "${assets_json}" "${manifest_name}"
import json
import sys

assets = json.load(open(sys.argv[1], encoding="utf-8"))["assets"]
target = sys.argv[2]
print("yes" if any(a.get("name") == target for a in assets) else "no")
PY
)

upload_list="${tmp_dir}/upload.txt"
skip_list="${tmp_dir}/skip.txt"
: > "${skip_list}"

if [[ "${manifest_present}" == "yes" ]]; then
  gh release download "${release_tag}" --pattern "${manifest_name}" --dir "${tmp_dir}" --clobber >/dev/null || {
    echo "Warning: Failed to download existing ${manifest_name}; uploading all selected files." >&2
    manifest_present="no"
  }
fi

if [[ "${manifest_present}" != "yes" ]]; then
  printf "{}" > "${manifest_path}"
  printf '%s\n' "${artifacts[@]}" > "${upload_list}"
else
  determine_script="${tmp_dir}/determine_uploads.py"
  cat > "${determine_script}" <<'PY'
import json
import os
import sys

updates_path, manifest_path, assets_path, manifest_name, upload_out, skip_out, *paths = sys.argv[1:]

updates = json.load(open(updates_path, encoding="utf-8"))
try:
    manifest = json.load(open(manifest_path, encoding="utf-8"))
except (FileNotFoundError, json.JSONDecodeError):
    manifest = {}

asset_names = {
    asset.get("name")
    for asset in json.load(open(assets_path, encoding="utf-8")).get("assets", [])
    if asset.get("name") and asset.get("name") != manifest_name
}

upload_paths = []
skipped = []

for path in paths:
    name = os.path.basename(path)
    checksum = updates.get(name)
    if checksum is None:
        upload_paths.append(path)
        continue
    if name in asset_names and manifest.get(name) == checksum:
        skipped.append(name)
    else:
        upload_paths.append(path)

with open(upload_out, "w", encoding="utf-8") as f:
    f.write("\n".join(upload_paths))

with open(skip_out, "w", encoding="utf-8") as f:
    f.write("\n".join(skipped))
PY
  "${python_cmd}" "${determine_script}" "${updates_json}" "${manifest_path}" "${assets_json}" "${manifest_name}" "${upload_list}" "${skip_list}" "${artifacts[@]}"
fi

artifacts_to_upload=()
if [[ -s "${upload_list}" ]]; then
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    artifacts_to_upload+=("${line}")
  done < "${upload_list}"
fi

if [[ "${#artifacts_to_upload[@]}" -eq 0 ]]; then
  echo "All selected files already match release ${release_tag}. Nothing to upload."
  exit 0
fi

uploaded_names_path="${tmp_dir}/uploaded_names.txt"
: > "${uploaded_names_path}"

for path in "${artifacts_to_upload[@]}"; do
  echo "[upload] $(basename "${path}")"
  "${SAFE_UPLOAD_SCRIPT}" "${release_tag}" "${path}" "$(basename "${path}")"
  printf '%s\n' "$(basename "${path}")" >> "${uploaded_names_path}"
done
gh release view "${release_tag}" --json assets > "${assets_json}"

"${python_cmd}" - <<'PY' "${manifest_path}" "${updates_json}"
import json
import sys

manifest_path = sys.argv[1]
updates = json.load(open(sys.argv[2], encoding="utf-8"))

with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(updates, f, indent=2, sort_keys=True)
PY

echo "[upload] ${manifest_name}"
"${SAFE_UPLOAD_SCRIPT}" "${release_tag}" "${manifest_path}" "${manifest_name}"
echo "Uploaded ${#artifacts_to_upload[@]} file(s) to release ${release_tag}."
