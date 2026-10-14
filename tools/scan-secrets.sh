#!/bin/sh
# =============================================================================
# scan-secrets.sh — the record is part of the attack surface
# =============================================================================
# Ported from an earlier engagement, where a live session id was committed while
# a finding was being written down. The scan extracts its patterns FROM THE
# VAULT AT RUN TIME — it never holds a literal — and fails when a vault value
# appears in the working tree or (with --history) in a Git patch.
# The staging index is not scanned separately. Coverage is limited to supported
# patterns and values extracted from available vaults.
#
# Vault sources, highest first:
#   $H1_SECRETS_FILES            colon-separated files or directories
#   <program>/secrets.local      program vault (untracked, mode 600)
#   <program>/cookies/           every file under it, if present
#
# Generic credential shapes are always scanned, no vault needed:
#   GitHub tokens, AWS keys, PEM private keys, OpenAI keys, Slack tokens,
#   Authorization: Bearer values. Cookie VALUES are caught only when the vault
#   names them (records legitimately quote cookie names and flags; a session
#   value is a leak only when it is one of ours).
#
# Usage: sh tools/scan-secrets.sh [repo_root] [--history]
# Exit:  0 clean · 1 leak found. A leak is reported as path:line only —
#        the tool never prints the value it found or any vault content.
# =============================================================================
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
HISTORY=0
[ "${2:-}" = "--history" ] && HISTORY=1

TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
LITS="$TMP/literals"
GREXS="$TMP/regexes"
VAULTS="$TMP/vaults"
HITS="$TMP/hits"
: > "$LITS"; : > "$GREXS"; : > "$VAULTS"; : > "$HITS"

# --- generic shapes (regexes; no literal is ever stored) ---------------------
cat > "$GREXS" <<'RE'
gh[pousr]_[A-Za-z0-9]{20,}
github_pat_[A-Za-z0-9_]{20,}
AKIA[0-9A-Z]{16}
-----BEGIN [A-Z ]*PRIVATE KEY-----
sk-[A-Za-z0-9]{32,}
xox[baprs]-[A-Za-z0-9-]{10,}
Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._~+/-]{24,}
RE

# --- vault discovery ---------------------------------------------------------
vault_sources() {
  [ -n "${H1_SECRETS_FILES:-}" ] && printf '%s\n' "$H1_SECRETS_FILES" | tr ':' '\n'
  for d in "$ROOT"/programs/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    [ -f "$d/secrets.local" ] && printf '%s\n' "$d/secrets.local"
    [ -d "$d/cookies" ] && find "$d/cookies" -type f 2>/dev/null
  done
}

vault_sources > "$TMP/vault-list"
while IFS= read -r v; do
  [ -n "$v" ] || continue
  if [ -d "$v" ]; then
    find "$v" -type f 2>/dev/null >> "$VAULTS"
  elif [ -f "$v" ]; then
    printf '%s\n' "$v" >> "$VAULTS"
  fi
done < "$TMP/vault-list"

norm() { printf '%s' "$1" | sed 's|//*|/|g'; }

while IFS= read -r v; do
  [ -f "$v" ] || continue
  rel="$(norm "${v#"$ROOT"/}")"
  # A versioned vault is itself a leak: the vault never travels with the repo.
  if git -C "$ROOT" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
    printf 'LEAK: vault file is tracked by git: %s\n' "$rel" | tee -a "$HITS"
  fi
  # Extract token-shaped values (>=16 chars) from NAME=value / NAME: value.
  sed -n 's/^[^:=]*[:=][[:space:]]*//p' "$v" \
    | grep -oE '[A-Za-z0-9._~+/=-]{16,}' >> "$LITS" 2>/dev/null || true
done < "$VAULTS"

if [ -s "$LITS" ]; then
  sort -u "$LITS" -o "$LITS"
  grep -v '^$' "$LITS" > "$LITS.tmp" 2>/dev/null || : > "$LITS.tmp"
  mv "$LITS.tmp" "$LITS"
fi

# --- scan the working tree (vault files excluded: that is their home) --------
collect() { # $1 = extra grep flag (-E or -F); stdin = pattern file
  pat="$1"
  grep -rIn "$pat" --exclude-dir=.git --exclude=scan-secrets.sh \
    -f "$2" "$ROOT" 2>/dev/null \
    | awk -F: -v root="$ROOT/" '{ p=$1; sub("^"root, "", p); print p":"$2 }'
}

{ [ -s "$GREXS" ] && collect -E "$GREXS" || true; } >> "$HITS"
{ [ -s "$LITS" ] && collect -F "$LITS" || true; } >> "$HITS"

# Drop hits that live inside a vault file (its legitimate home).
if [ -s "$VAULTS" ] && [ -s "$HITS" ]; then
  while IFS= read -r v; do
    rel="$(norm "${v#"$ROOT"/}")"
    grep -vF "$rel:" "$HITS" > "$HITS.tmp" 2>/dev/null || : > "$HITS.tmp"
    mv "$HITS.tmp" "$HITS"
  done < "$VAULTS"
fi

# --- optional: the same values must not exist in history ---------------------
if [ "$HISTORY" = 1 ] && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  if [ -s "$GREXS" ] && git -C "$ROOT" log -p --all 2>/dev/null | grep -qE -f "$GREXS"; then
    printf 'LEAK: generic credential shape found in git history (--history)\n' >> "$HITS"
  fi
  if [ -s "$LITS" ] && git -C "$ROOT" log -p --all 2>/dev/null | grep -qF -f "$LITS"; then
    printf 'LEAK: vault-derived value found in git history (--history)\n' >> "$HITS"
  fi
fi

# --- verdict -----------------------------------------------------------------
if [ -s "$HITS" ]; then
  sort -u "$HITS" | while IFS= read -r hit; do
    printf '  %s\n' "$hit"
  done
  echo "scan-secrets: LEAK — the value is never printed; open the location."
  exit 1
fi
if [ -s "$VAULTS" ]; then
  echo "scan-secrets: clean (vault-driven: $(wc -l < "$VAULTS" | tr -d ' ') vault file(s), $(wc -l < "$LITS" | tr -d ' ') value(s))"
else
  echo "scan-secrets: clean (generic shapes only; no vault present)"
fi
exit 0
