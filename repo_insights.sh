#!/usr/bin/env bash
# repo_insights.sh — macOS-friendly, no mapfile
# Saves EVERY run into a timestamped folder and supports optional date/time filters.
# Author grouping FIXED: now grouped by GitHub username (deduped)
# Output folder per run:
#    run_<YYYYmmdd_HHMMSS>/
# Includes:
#    repo_stats.csv
#    prs_all.csv
#    authors_summary.csv (DEDUPE FIXED)
#    committers_summary.csv
#    commits_detailed.csv
#    users/<github_login>.csv

set -euo pipefail

err(){ echo "❌ $*" >&2; exit 1; }

############################
# Parse date filters
############################
SINCE=""; UNTIL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)  shift; SINCE="${1:-}";;
    --until)  shift; UNTIL="${1:-}";;
  esac
  shift || true
done

############################
# Repo check
############################
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
  err "Run this INSIDE a cloned repo."

REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
[[ -z "$REMOTE_URL" ]] && err "No 'origin' remote found."

REPO=$(echo "$REMOTE_URL" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')
[[ "$REPO" != *"/"* ]] && err "Could not parse owner/repo."

if ! gh auth status >/dev/null 2>&1; then
  err "GitHub CLI not logged in. Run: gh auth login"
fi

############################
# Output folder
############################
OUT_BASE="repo_insights_output"
TS="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="${OUT_BASE}/run_${TS}"
mkdir -p "${RUN_DIR}/users"
mkdir -p "$OUT_BASE"

echo "$TS  $RUN_DIR" >> "${OUT_BASE}/history_runs.txt"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "📌 Repo: $REPO"
[[ -n "$SINCE" ]] && echo "⏱  Since: $SINCE"
[[ -n "$UNTIL" ]] && echo "⏱  Until: $UNTIL"

############################################
# A) Fetch PRs
############################################
echo "➡ Fetching PRs…"

gh pr list --repo "$REPO" --state all --limit 3000 \
  --json number,title,state,isDraft,author,mergedBy,createdAt,mergedAt,closedAt,baseRefName,headRefName \
  > "$TMPDIR/prs.json"

jq -r --arg since "$SINCE" --arg until "$UNTIL" '
  def in_window(dt):
    ($since=="" and $until=="") or
    ($since=="" and dt<= $until) or
    ($until=="" and dt>= $since) or
    (dt>= $since and dt<= $until);

  .[]
  | select( ($since=="" and $until=="") or in_window(.createdAt) or in_window(.mergedAt) or in_window(.closedAt) )
  | [
      .number,
      (.title|gsub("\"";"\"\"")),
      .state,
      .isDraft,
      .author.login,
      (.mergedBy.login // ""),
      .createdAt,
      (.mergedAt // ""),
      (.closedAt // ""),
      .headRefName,
      .baseRefName
    ] | @csv
' "$TMPDIR/prs.json" \
| awk 'BEGIN{
     print "number,title,state,is_draft,opened_by,merged_by,created_at,merged_at,closed_at,head,base"
   } {print}' > "${RUN_DIR}/prs_all.csv"

PRS_OPENED=$(tail -n +2 "${RUN_DIR}/prs_all.csv" | wc -l | tr -d ' ')
PRS_MERGED=$(awk -F, 'NR>1 && $8!="" {c++} END{print c+0}' "${RUN_DIR}/prs_all.csv")

############################################
# B) Commits (per commit stats)
############################################
echo "➡ Scanning commits…"

GIT_RANGE_ARGS=()
[[ -n "$SINCE" ]] && GIT_RANGE_ARGS+=(--since "$SINCE")
[[ -n "$UNTIL" ]] && GIT_RANGE_ARGS+=(--until "$UNTIL")

git rev-list "${GIT_RANGE_ARGS[@]}" --all > "$TMPDIR/all_shas.txt"

echo "sha,author_name,author_email,author_date,committer_name,committer_email,committer_date,additions,deletions,files_changed" \
  > "${RUN_DIR}/commits_detailed.csv"

TOTAL_COMMITS=0; TOTAL_ADD=0; TOTAL_DEL=0; TOTAL_FILES=0

# TEMP for dedupe by login
: > "$TMPDIR/sha_login.csv"

while IFS= read -r SHA; do
  [ -z "$SHA" ] && continue
  TOTAL_COMMITS=$((TOTAL_COMMITS+1))

  # Extract author identity from git
  IFS=$'\t' read -r AN AE AD CN CE CD <<EOF
$(git show -s --no-use-mailmap --date=iso-strict --pretty=$'%an\t%ae\t%ad\t%cn\t%ce\t%cd' "$SHA")
EOF

  # GitHub Login via API (exact)
  LOGIN=$(gh api "repos/$REPO/commits/$SHA" -q '.author.login // empty' 2>/dev/null || true)
  echo "$SHA,$LOGIN" >> "$TMPDIR/sha_login.csv"

  # Diff stats
  A=0; D=0; F=0
  git show --numstat --format="" "$SHA" > "$TMPDIR/numstat.txt" || true
  while IFS=$'\t' read -r add del path; do
    [ -z "$path" ] && continue
    [[ "$add" = "-" ]] && add=0
    [[ "$del" = "-" ]] && del=0
    A=$((A+add)); D=$((D+del)); F=$((F+1))
  done < "$TMPDIR/numstat.txt"

  TOTAL_ADD=$((TOTAL_ADD+A))
  TOTAL_DEL=$((TOTAL_DEL+D))
  TOTAL_FILES=$((TOTAL_FILES+F))

  esc(){ printf %s "$1" | sed 's/"/""/g'; }

  printf '%s,"%s","%s","%s","%s","%s","%s",%d,%d,%d\n' \
    "$SHA" "$(esc "$AN")" "$(esc "$AE")" "$(esc "$AD")" \
    "$(esc "$CN")" "$(esc "$CE")" "$(esc "$CD")" \
    "$A" "$D" "$F" \
    >> "${RUN_DIR}/commits_detailed.csv"

done < "$TMPDIR/all_shas.txt"

############################################
# C) Authors grouped correctly by GitHub login
############################################
awk -F, '
  BEGIN{
    print "user,total_commits,total_additions,total_deletions"
  }
  NR==FNR {
    # sha_login.csv: sha,login
    sha=$1; login=$2
    sub(/\r$/,"",login)
    sha2login[sha]=login
    next
  }
  NR>1 {
    sha=$1
    add=$9+0
    del=$10+0

    user=sha2login[sha]
    if(user==""){
      # fallback: normalize author_name
      n=$2
      gsub(/^"|"$/,"",n)
      user=tolower(n)
      gsub(/[[:space:]]+/," ",user)
    }

    commits[user]++
    adds[user]+=add
    dels[user]+=del
  }
  END{
    for (u in commits){
      printf "%s,%d,%d,%d\n", u, commits[u], adds[u], dels[u]
    }
  }
' "$TMPDIR/sha_login.csv" "${RUN_DIR}/commits_detailed.csv" \
  | sort > "${RUN_DIR}/authors_summary.csv"

############################################
# D) Raw committer summary (optional)
############################################
awk -F, '
  NR>1 {
    n=$5; e=$6; add=$9; del=$10
    key=n"|"e
    commits[key]++
    adds[key]+=add
    dels[key]+=del
  }
  END{
    print "committer_name,committer_email,total_commits,total_additions,total_deletions"
    for (k in commits){
      split(k,a,"|")
      printf "\"%s\",\"%s\",%d,%d,%d\n", a[1], a[2], commits[k], adds[k], dels[k]
    }
  }
' "${RUN_DIR}/commits_detailed.csv" \
| sort > "${RUN_DIR}/committers_summary.csv"

############################################
# E) Per-user commit files
############################################
python3 - "${RUN_DIR}/commits_detailed.csv" "$TMPDIR/sha_login.csv" "${RUN_DIR}/users" << 'PY'
import csv, os, sys
commits_file, map_file, users_dir = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(users_dir, exist_ok=True)

# load sha->login
sha_login = {}
with open(map_file) as f:
    for line in f:
        sha, login = line.strip().split(",", 1)
        sha_login[sha] = login or None

rows = []
with open(commits_file) as f:
    r = csv.DictReader(f)
    for row in r:
        rows.append(row)

by_user = {}
for r in rows:
    sha = r["sha"]
    login = sha_login.get(sha)
    if not login:
        login = r["author_name"].lower().strip()
    by_user.setdefault(login, []).append(r)

def slug(s):
    import re
    return re.sub(r"[^A-Za-z0-9._-]+", "_", s)[:80] or "unknown"

for user, commits in by_user.items():
    fn = os.path.join(users_dir, f"{slug(user)}.csv")
    with open(fn, "w") as f:
        w = csv.DictWriter(f, fieldnames=rows[0].keys())
        w.writeheader()
        w.writerows(commits)
PY

############################################
# F) Repo totals
############################################
{
  echo "Pull Requests Opened (Raw),Pull Requests Merged (Raw),Commits (Raw),Files (Raw),Additions (Raw),Deletions (Raw)"
  echo "${PRS_OPENED},${PRS_MERGED},${TOTAL_COMMITS},${TOTAL_FILES},${TOTAL_ADD},${TOTAL_DEL}"
} > "${RUN_DIR}/repo_stats.csv"

echo "✅ Done!"
echo "📂 Results saved in: ${RUN_DIR}"
