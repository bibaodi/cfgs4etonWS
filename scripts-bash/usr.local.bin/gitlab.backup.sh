#!/bin/bash
eton@260910 for gitlab backup all repos ;

# --- Configuration ---
GITLAB_URL="http://192.168.0.244"
TOKEN_FILE="$HOME/.gitlab.token"
MIRROR_DIR="$HOME/gitlab_backups/mirrors"
LOG_FILE="$HOME/gitlab_backups/backup.log"

# --resolve macOS Keychain error:failed to store: -25308.begin;
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=credential.helper
export GIT_CONFIG_VALUE_0=
# --resolve macOS Keychain error:failed to store: -25308.end;

# --- helpers ---
function clean_err_log(){
	# Keep only the last 5000 lines
	[ -f "$LOG_FILE" ] && tail -n 5000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
}
function log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}
function die() {
  echo "ERROR: $1" >&2
  echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $1" >> "$LOG_FILE"
  exit 1
}

# --- helpers.end ---

log "=== Backup run started ==="
mkdir -p "$(dirname "$LOG_FILE")"
TOKEN=$(cat "$TOKEN_FILE")
mkdir -p "$MIRROR_DIR"

# =========================================================
# Token content check (non-empty, no stray whitespace)
# =========================================================
if [ ! -f "$TOKEN_FILE" ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: token file not found at $TOKEN_FILE" | tee -a "$LOG_FILE"
  exit 1
fi
if [ -z "$TOKEN" ]; then
  die "Token file is not preset or empty: $TOKEN_FILE
   Add a GitLab Personal Access Token with the 'api' scope."
fi

# --- Fetch list of repositories (paginated) ---
REPO_LIST=$(mktemp)
PAGE=1
while true; do
  RESPONSE=$(curl -sS --header "PRIVATE-TOKEN: $TOKEN" \
    "${GITLAB_URL}/api/v4/projects?membership=true&per_page=100&page=${PAGE}")
  COUNT=$(echo "$RESPONSE" | jq 'length')
  [ "$COUNT" -eq 0 ] && break
  echo "$RESPONSE" | jq -r '.[].http_url_to_repo' >> "$REPO_LIST"
  PAGE=$((PAGE + 1))
done

TOTAL=$(wc -l < "$REPO_LIST" | tr -d ' ')
log "Found $TOTAL repositories"

# --- Clone or update each mirror ---
while IFS= read -r repo_url; do
  # Derive local path, e.g. sw/webusis.git -> mirrors/sw/webusis.git
  repo_path=$(echo "$repo_url" | sed "s|${GITLAB_URL}/||")
  local_path="$MIRROR_DIR/$repo_path"

  # Inject token for auth
  auth_url=$(echo "$repo_url" | sed "s|http://|http://oauth2:${TOKEN}@|")

  mkdir -p "$(dirname "$local_path")"

  if [ -d "$local_path" ]; then
    # --- Incremental update ---
    if git -C "$local_path" remote update --prune >> "$LOG_FILE" 2>&1; then
      log "UPDATED  $repo_path"
    else
      log "FAILED   $repo_path (update)"
    fi
  else
    # --- First-time clone ---
    if git clone --mirror "$auth_url" "$local_path" >> "$LOG_FILE" 2>&1; then
      log "CLONED   $repo_path"
    else
      log "FAILED   $repo_path (clone)"
    fi
  fi
done < "$REPO_LIST"

rm -f "$REPO_LIST"
log "=== Backup run finished ==="

function restore(){
# Clone from the mirror into a working tree
git clone ~/gitlab_backups/mirrors/sw/webusis.git ~/restored/webusis

# Or push the mirror to a new GitLab remote
cd ~/gitlab_backups/mirrors/sw/webusis.git
git push --mirror http://new-gitlab.example.com/sw/webusis.git
}

