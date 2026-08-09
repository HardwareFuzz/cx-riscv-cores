#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/upload_release_asset_safe.sh <tag> <file> [asset_name]

Behavior:
  1. Upload the file to the release under a temporary asset name with curl progress.
  2. Optionally delete the old asset of the target name.
  3. Rename the temporary asset to the final asset name.
  4. Verify the final asset size and SHA256 using GitHub's server-side digest.
     Fall back to downloading the asset only when the API does not expose a digest.

Why this exists:
  gh release upload --clobber deletes the old asset before uploading the new one.
  If the upload stalls or fails, the release can be left without that asset.

Environment overrides:
  GITHUB_REPO            Default: HardwareFuzz/cx-riscv-cores
  CURL_LOW_SPEED_BPS     Default: 10240   (10 KiB/s)
  CURL_LOW_SPEED_TIME    Default: 600     (seconds)
  CURL_CONNECT_TIMEOUT   Default: 15      (seconds)
  CURL_HTTP_VERSION      Default: --http1.1
  CURL_LIMIT_RATE        Optional. Example: 256k
  CURL_RESOLVE_ENTRY     Optional. Example: uploads.github.com:443:20.205.243.161
  UPLOAD_RETRIES         Default: 3
  UPLOAD_RETRY_DELAY     Default: 10      (seconds)
  DELETE_RETRIES         Default: 3
  VERIFY_RETRIES         Default: 3
  VERIFY_RETRY_DELAY     Default: 5       (seconds)
EOF
}

[[ $# -ge 2 && $# -le 3 ]] || { usage >&2; exit 1; }

TAG="$1"
FILE="$2"
ASSET_NAME="${3:-$(basename "$FILE")}"
REPO="${GITHUB_REPO:-HardwareFuzz/cx-riscv-cores}"
LOW_SPEED_BPS="${CURL_LOW_SPEED_BPS:-10240}"
LOW_SPEED_TIME="${CURL_LOW_SPEED_TIME:-600}"
CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-15}"
HTTP_VERSION_FLAG="${CURL_HTTP_VERSION:---http1.1}"
LIMIT_RATE="${CURL_LIMIT_RATE:-}"
RESOLVE_ENTRY="${CURL_RESOLVE_ENTRY:-}"
UPLOAD_RETRIES="${UPLOAD_RETRIES:-3}"
UPLOAD_RETRY_DELAY="${UPLOAD_RETRY_DELAY:-10}"
DELETE_RETRIES="${DELETE_RETRIES:-3}"
VERIFY_RETRIES="${VERIFY_RETRIES:-3}"
VERIFY_RETRY_DELAY="${VERIFY_RETRY_DELAY:-5}"

[[ -f "$FILE" ]] || { echo "ERROR: file not found: $FILE" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh is required" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required" >&2; exit 1; }

RELEASE_JSON="$(gh api "repos/${REPO}/releases/tags/${TAG}")"
RELEASE_ID="$(python3 - <<'PY' "$RELEASE_JSON"
import json, sys
print(json.loads(sys.argv[1])["id"])
PY
)"
UPLOAD_URL="https://uploads.github.com/repos/${REPO}/releases/${RELEASE_ID}/assets"
TOKEN="$(gh auth token)"
TMP_RESP="$(mktemp)"
FILE_SIZE="$(stat -c '%s' "$FILE")"
ASSETS_API_PATH="repos/${REPO}/releases/${RELEASE_ID}/assets?per_page=100"
VERIFY_TMP_DIR=""

sha256_of() {
  python3 - <<'PY' "$1"
import hashlib
import sys

path = sys.argv[1]
h = hashlib.sha256()
with open(path, "rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        if not chunk:
            break
        h.update(chunk)
print(h.hexdigest())
PY
}

LOCAL_SHA256="$(sha256_of "$FILE")"

cleanup() {
  rm -f "$TMP_RESP"
  if [[ -n "${VERIFY_TMP_DIR}" ]]; then
    rm -rf "${VERIFY_TMP_DIR}"
  fi
}
trap cleanup EXIT

echo "release=${TAG}"
echo "repo=${REPO}"
echo "file=${FILE}"
echo "target_name=${ASSET_NAME}"
echo "low_speed=${LOW_SPEED_BPS}B/s for ${LOW_SPEED_TIME}s"
[[ -n "${LIMIT_RATE}" ]] && echo "limit_rate=${LIMIT_RATE}"
[[ -n "${RESOLVE_ENTRY}" ]] && echo "resolve=${RESOLVE_ENTRY}"
echo "retries=${UPLOAD_RETRIES}"
echo "delete_retries=${DELETE_RETRIES}"
echo "verify_retries=${VERIFY_RETRIES}"
echo

TMP_ASSET_ID=""
TMP_ASSET_SIZE=""
TMP_NAME=""
attempt=1

while (( attempt <= UPLOAD_RETRIES )); do
  TMP_NAME="${ASSET_NAME}.uploading.$(date +%Y%m%d%H%M%S).$$.${attempt}"
  echo "[1/4] Upload temp asset with live progress (attempt ${attempt}/${UPLOAD_RETRIES})"
  echo "temp_name=${TMP_NAME}"
  : > "$TMP_RESP"

  curl_args=(
    "$HTTP_VERSION_FLAG"
    ${RESOLVE_ENTRY:+--resolve "$RESOLVE_ENTRY"}
    --progress-bar
    --connect-timeout "$CONNECT_TIMEOUT"
    --speed-limit "$LOW_SPEED_BPS"
    --speed-time "$LOW_SPEED_TIME"
    --output "$TMP_RESP"
    --write-out '%{http_code}'
    -X POST
    -H "Authorization: Bearer ${TOKEN}"
    -H "Accept: application/vnd.github+json"
    -H "Content-Type: application/octet-stream"
    -H "Expect:"
    --data-binary @"$FILE"
    "${UPLOAD_URL}?name=${TMP_NAME}"
  )
  if [[ -n "${LIMIT_RATE}" ]]; then
    curl_args=(--limit-rate "${LIMIT_RATE}" "${curl_args[@]}")
  fi

  set +e
  CURL_HTTP_CODE="$(curl "${curl_args[@]}")"
  curl_status=$?
  set -e
  echo

  if [[ $curl_status -eq 0 && "$CURL_HTTP_CODE" == "201" ]]; then
    TMP_ASSET_ID="$(python3 - <<'PY' "$TMP_RESP"
import json, sys
obj = json.load(open(sys.argv[1]))
print(obj["id"])
PY
)"
    TMP_ASSET_SIZE="$(python3 - <<'PY' "$TMP_RESP"
import json, sys
obj = json.load(open(sys.argv[1]))
print(obj["size"])
PY
)"
    if [[ "$TMP_ASSET_SIZE" != "$FILE_SIZE" ]]; then
      echo "WARNING: uploaded temp asset size ${TMP_ASSET_SIZE} != local file size ${FILE_SIZE}" >&2
      gh api -X DELETE "repos/${REPO}/releases/assets/${TMP_ASSET_ID}" >/dev/null 2>&1 || true
    else
      break
    fi
  else
    echo "WARNING: upload attempt ${attempt} failed (curl_status=${curl_status}, http=${CURL_HTTP_CODE:-n/a})" >&2
    sed -n '1,40p' "$TMP_RESP" >&2 || true
  fi

  # If a partial temp asset somehow made it onto the release, remove it before retrying.
  partial_id="$(
    gh api --paginate "${ASSETS_API_PATH}" \
      --jq ".[] | select(.name == \"${TMP_NAME}\") | .id" 2>/dev/null || true
  )"
  if [[ -n "${partial_id}" ]]; then
    gh api -X DELETE "repos/${REPO}/releases/assets/${partial_id}" >/dev/null 2>&1 || true
  fi

  (( attempt++ ))
  if (( attempt <= UPLOAD_RETRIES )); then
    echo "Retrying in ${UPLOAD_RETRY_DELAY}s..."
    sleep "${UPLOAD_RETRY_DELAY}"
  fi
done

if [[ -z "${TMP_ASSET_ID}" || "${TMP_ASSET_SIZE}" != "${FILE_SIZE}" ]]; then
  echo "ERROR: upload failed after ${UPLOAD_RETRIES} attempt(s)" >&2
  exit 1
fi

echo "[2/4] Query old asset"
OLD_ASSET_ID="$(
  gh api --paginate "${ASSETS_API_PATH}" \
    --jq ".[] | select(.name == \"${ASSET_NAME}\") | .id" 2>/dev/null || true
)"

if [[ -n "${OLD_ASSET_ID}" ]]; then
  echo "Deleting old asset id=${OLD_ASSET_ID}"
  delete_attempt=1
  while true; do
    if gh api \
      -X DELETE \
      "repos/${REPO}/releases/assets/${OLD_ASSET_ID}" >/dev/null
    then
      break
    fi

    if (( delete_attempt >= DELETE_RETRIES )); then
      echo "ERROR: failed to delete old asset id=${OLD_ASSET_ID} after ${DELETE_RETRIES} attempt(s)" >&2
      exit 1
    fi

    echo "WARNING: delete attempt ${delete_attempt}/${DELETE_RETRIES} failed for asset id=${OLD_ASSET_ID}; retrying in 3s..." >&2
    delete_attempt=$((delete_attempt + 1))
    sleep 3
  done
else
  echo "No existing asset named ${ASSET_NAME}"
fi

echo "[3/4] Rename temp asset to final name"
gh api \
  -X PATCH \
  "repos/${REPO}/releases/assets/${TMP_ASSET_ID}" \
  -f name="${ASSET_NAME}" >/dev/null

echo "[4/4] Verify final asset"
FINAL_ASSET_TSV="$(
  gh api --paginate "${ASSETS_API_PATH}" \
    --jq ".[] | select(.name == \"${ASSET_NAME}\") | [.name, .updated_at, (.size|tostring), (.digest // \"\"), .browser_download_url] | @tsv"
)"
if [[ -z "${FINAL_ASSET_TSV}" ]]; then
  echo "ERROR: final asset ${ASSET_NAME} was not found after rename" >&2
  exit 1
fi
printf '%s\n' "${FINAL_ASSET_TSV}"

FINAL_ASSET_SIZE="$(printf '%s\n' "${FINAL_ASSET_TSV}" | cut -f3)"
FINAL_ASSET_DIGEST="$(printf '%s\n' "${FINAL_ASSET_TSV}" | cut -f4)"
EXPECTED_DIGEST="sha256:${LOCAL_SHA256}"

if [[ "${FINAL_ASSET_SIZE}" != "${FILE_SIZE}" ]]; then
  echo "ERROR: final asset ${ASSET_NAME} size ${FINAL_ASSET_SIZE} != local file size ${FILE_SIZE}" >&2
  exit 1
fi

if [[ -n "${FINAL_ASSET_DIGEST}" ]]; then
  if [[ "${FINAL_ASSET_DIGEST}" != "${EXPECTED_DIGEST}" ]]; then
    echo "ERROR: final asset ${ASSET_NAME} server digest mismatch" >&2
    echo "  expected_digest=${EXPECTED_DIGEST}" >&2
    echo "  actual_digest=${FINAL_ASSET_DIGEST}" >&2
    exit 1
  fi

  printf 'verified_sha256=%s\n' "${LOCAL_SHA256}"
  echo "verification=github_api_digest"
  exit 0
fi

echo "GitHub API did not expose a digest; falling back to release download verification."

VERIFY_TMP_DIR="$(mktemp -d)"

verify_attempt=1
while (( verify_attempt <= VERIFY_RETRIES )); do
  rm -f "${VERIFY_TMP_DIR}/${ASSET_NAME}"

  if gh release download "${TAG}" -R "${REPO}" --pattern "${ASSET_NAME}" --dir "${VERIFY_TMP_DIR}" --clobber >/dev/null 2>&1; then
    DOWNLOADED_FILE="${VERIFY_TMP_DIR}/${ASSET_NAME}"
    if [[ -f "${DOWNLOADED_FILE}" ]]; then
      DOWNLOADED_SIZE="$(stat -c '%s' "${DOWNLOADED_FILE}")"
      DOWNLOADED_SHA256="$(sha256_of "${DOWNLOADED_FILE}")"
      if [[ "${DOWNLOADED_SIZE}" == "${FILE_SIZE}" && "${DOWNLOADED_SHA256}" == "${LOCAL_SHA256}" ]]; then
        printf 'verified_sha256=%s\n' "${LOCAL_SHA256}"
        break
      fi

      echo "WARNING: verify attempt ${verify_attempt}/${VERIFY_RETRIES} downloaded asset mismatch" >&2
      echo "  expected_size=${FILE_SIZE} actual_size=${DOWNLOADED_SIZE}" >&2
      echo "  expected_sha256=${LOCAL_SHA256}" >&2
      echo "  actual_sha256=${DOWNLOADED_SHA256}" >&2
    else
      echo "WARNING: verify attempt ${verify_attempt}/${VERIFY_RETRIES} did not produce ${ASSET_NAME}" >&2
    fi
  else
    echo "WARNING: verify attempt ${verify_attempt}/${VERIFY_RETRIES} failed to download ${ASSET_NAME}" >&2
  fi

  if (( verify_attempt == VERIFY_RETRIES )); then
    echo "ERROR: final asset ${ASSET_NAME} failed release-content verification" >&2
    exit 1
  fi

  verify_attempt=$((verify_attempt + 1))
  sleep "${VERIFY_RETRY_DELAY}"
done
