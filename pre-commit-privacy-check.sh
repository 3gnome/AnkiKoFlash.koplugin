#!/usr/bin/env bash
# pre-commit-privacy-check.sh — block commits/pushes/deploys that leak personal data.
#
# Scans staged + unstaged + untracked (gitignore-respecting) changes for:
#   * personal home paths (e.g. /mnt/c/Users/<you>, C:\Users\<you>, /home/<you>)
#   * private LAN IPs (e.g. 192.168.x.y, 10.x.y.z, 172.16-31.x.y)
#   * email addresses
#   * private keys
#   * hardcoded secrets (non-placeholder values)
#
# Documented placeholders used in docs/samples are whitelisted so they do not
# false-positive (192.168.1.100 / 192.168.1.50 / 192.168.x.x, YOUR_*_KEY, <you>,
# example.com, etc.).
#
# Usage:
#   bash pre-commit-privacy-check.sh          # run before commit / push / deploy
#   SKIP_PRIVACY_CHECK=1 bash ...             # explicit override (use sparingly)
#
# Optional one-time git hook (blocked by default, so you always see a failure):
#   ln -s ../../pre-commit-privacy-check.sh .git/hooks/pre-commit
set -u

cd "$(dirname "$0")" || exit 1

files="$(
  { git diff --cached --name-only --diff-filter=ACMR
    git diff --name-only --diff-filter=ACMR
    git ls-files --others --exclude-standard; } 2>/dev/null | sort -u
)"

if [ -z "$files" ]; then
  echo "[privacy] OK — no changes to scan."
  exit 0
fi

# rule = "label|pattern"
rules=(
  "personal home path|/mnt/c/Users/[A-Za-z0-9_.-]+|C:[\\\\/]Users[\\\\/][A-Za-z0-9_.-]+|/home/[A-Za-z0-9_.-]+|/Users/[A-Za-z0-9_.-]+"
  "private LAN IP|(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.)[0-9]{1,3}\.[0-9]{1,3}"
  "email address|[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+"
  "private key|-----BEGIN [A-Z ]*PRIVATE KEY-----"
  "hardcoded secret|(api_?key|apikey|access_?token|secret|password|passwd)[\"']?[[:space:]]*[:=][[:space:]]*[\"'][A-Za-z0-9+/_=-]{20,}[\"']"
)

# Whitelist filter for documented placeholders (applied to every rule's hits).
whitelist='192\.168\.(1\.100|1\.50|x\.x|0\.100|1\.1)|10\.0\.0\.(x|[1-9]|10)|YOUR_[A-Z_]+|REPLACE_ME|changeme|<you>|/mnt/c/Users/(<you>|you|yourname|YOUR|USERNAME)|C:[\\/]Users[\\/](<you>|you|yourname|YOUR|USERNAME)|/home/(<you>|you|yourname|YOUR|USERNAME)|/Users/(<you>|you|yourname|YOUR|USERNAME)|(example|yourname|you|user|test|noreply)@|@example\.|example\.(com|org|net)'

found=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  for rule in "${rules[@]}"; do
    label="${rule%%|*}"
    pattern="${rule#*|}"
    hits="$(grep -nE "$pattern" "$f" 2>/dev/null | grep -vE "$whitelist")"
    if [ -n "$hits" ]; then
      echo "[privacy] $label  ->  $f"
      echo "$hits" | sed 's/^/    /'
      found=1
    fi
  done
done <<< "$files"

if [ "$found" -ne 0 ]; then
  echo ""
  echo "[privacy] BLOCKED: personal data detected above. Replace it with a"
  echo "[privacy] placeholder (e.g. 192.168.x.x, YOUR_API_KEY, /mnt/c/Users/<you>)"
  echo "[privacy] and re-run. Override only with explicit approval:"
  echo "[privacy]   SKIP_PRIVACY_CHECK=1 bash pre-commit-privacy-check.sh"
  exit 1
fi

echo "[privacy] OK — no personal data found."
exit 0
