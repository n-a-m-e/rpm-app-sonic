#!/usr/bin/env bash
set -euo pipefail

OUT=${OUT:-sonicde-specs}
LOG=${LOG:-build-discovery.log}
ORG=${ORG:-OpenMandrivaAssociation}
TERMS=(sonic silver)
BRANCHES=(master main rolling)
BLACKLIST=(sonic sonic-visualiser python-silvercity rust-silver)

log(){ printf '[%s] %s\n' "$(date -u +'%H:%M:%S')" "$*" | tee -a "$LOG" >&2; }
die(){ log "ERROR: $*"; exit 1; }
norm(){ tr '[:upper:]' '[:lower:]' <<<"$1" | sed -E 's/[^a-z0-9]//g'; }
blacklisted(){ local x="${1,,}" b; for b in "${BLACKLIST[@]}"; do [[ "$x" == "${b,,}" ]] && return 0; done; return 1; }
need(){ local c; for c in curl tar git package-build-queue; do command -v "$c" >/dev/null || die "$c missing"; done; }
add(){ local p="$1"; [[ -n "$p" ]] || return 0; blacklisted "$p" && { log "Skip blacklisted package: $p"; return 0; }; grep -Fxq "$p" "$OUT/.packages" 2>/dev/null || printf '%s\n' "$p" >> "$OUT/.packages"; }

init(){ rm -rf "$OUT" .repos.tsv "$LOG"; mkdir -p "$OUT"; : >"$OUT/.packages"; : >"$LOG"; }

targets(){
  printf '%s\n' "${TARGETS:-}" | tr ', ' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;/^$/d'
}

target_layers(){
  local target="$1" family part layer=""
  family="${target%-*}"

  IFS='-' read -r -a parts <<< "$family"
  for part in "${parts[@]}"; do
    [[ -n "$part" ]] || continue
    layer="${layer:+$layer-}$part"
    printf '%s\n' "$layer"
  done

  [[ "$target" == "$family" ]] || printf '%s\n' "$target"
}

spec_dirs(){
  local target layer dir
  declare -A seen=()

  if [[ -d specs ]]; then
    seen[specs]=1
    printf '%s\n' specs
  fi

  if targets | grep -q .; then
    while IFS= read -r target; do
      while IFS= read -r layer; do
        dir="$layer/specs"
        [[ -d "$dir" && -z "${seen[$dir]:-}" ]] || continue
        seen[$dir]=1
        printf '%s\n' "$dir"
      done < <(target_layers "$target")
    done < <(targets)
  else
    while IFS= read -r dir; do
      [[ -z "${seen[$dir]:-}" ]] || continue
      seen[$dir]=1
      printf '%s\n' "$dir"
    done < <(find . -mindepth 2 -maxdepth 2 -type d -name specs | sed 's#^./##' | LC_ALL=C sort)
  fi
}

layered_specs(){
  local dir
  while IFS= read -r dir; do
    find "$dir" -maxdepth 1 -type f -name '*.spec'
  done < <(spec_dirs) | LC_ALL=C sort
}

local_specs_available(){ layered_specs | grep -q .; }

report_local_specs(){
  local count
  count=$(layered_specs | wc -l | tr -d '[:space:]')
  [[ "$count" -gt 0 ]] || { log 'No local layered specs found'; return 0; }
  log "Local layered specs found: $count"
}

discover(){
  local term tmp full repo key n=0
  declare -A seen=()
  log 'GitHub lookup'
  : > .repos.tsv

  for term in "${TERMS[@]}"; do
    tmp=$(mktemp)
    if ! curl -fsSL --retry 3 --retry-delay 2 \
      -H 'Accept: application/vnd.github+json' -H 'User-Agent: sonicde-build-queue' \
      "https://api.github.com/search/repositories?q=${term}%20in:name,description+org:${ORG}&per_page=100" -o "$tmp"; then
      rm -f "$tmp"
      die "GitHub lookup failed: $term"
    fi

    while IFS= read -r full; do
      repo=${full##*/}; key=$(norm "$repo")
      [[ -n "$repo" && -n "$key" && -z "${seen[$key]:-}" ]] || continue
      seen[$key]=1
      blacklisted "$repo" && { log "Skip blacklisted GitHub repo: $repo"; continue; }
      printf '%s\t%s\n' "$repo" "$full" >> .repos.tsv
      n=$((n + 1))
    done < <(grep -aoE '"full_name"[[:space:]]*:[[:space:]]*"[^"/]+/[^"/]+"' "$tmp" | sed -E 's/.*"([^"]+\/[^"]+)"/\1/' || true)
    rm -f "$tmp"
  done

  if [[ ! -s .repos.tsv ]]; then
    local_specs_available && { log 'No GitHub package repos found; using local layered specs only'; return 0; }
    die 'GitHub lookup returned no package repos'
  fi

  cut -f1 .repos.tsv | sort -u > "$OUT/.discovered-repos"
  awk -F '\t' 'BEGIN{OFS="\t"} {print $1, "https://github.com/" $2}' .repos.tsv > "$OUT/.repo-map.tsv"
  log "Discovered package repos: $n"
}

fetch(){
  local repo="$1" full="$2" b tmp archive
  tmp=$(mktemp -d)

  for b in "${BRANCHES[@]}"; do
    rm -rf "$OUT/$repo" "$tmp/repo.tar.gz"
    mkdir -p "$OUT/$repo"
    archive="https://codeload.github.com/$full/tar.gz/$b"

    if curl -fsSL --retry 3 --retry-delay 2 "$archive" -o "$tmp/repo.tar.gz" 2>"$tmp/curl-$b.err" && \
       tar -xzf "$tmp/repo.tar.gz" -C "$OUT/$repo" --strip-components=1 2>"$tmp/tar-$b.err" && \
       [[ -f "$OUT/$repo/$repo.spec" ]]; then
      log "Fetched package repo: $repo ($b)"
      rm -rf "$tmp"
      add "$repo"
      return 0
    fi
  done

  rm -rf "$tmp" "$OUT/$repo"
  die "could not fetch package repo with root spec: $repo"
}

fetch_all(){
  local repo full
  [[ -s .repos.tsv ]] || return 0
  log 'Fetching discovered package repos'
  while IFS=$'\t' read -r repo full; do
    [[ -n "$repo" ]] || continue
    [[ ! -d "$OUT/$repo" ]] || die "discovered repo conflicts with existing package directory: $repo"
    fetch "$repo" "$full"
  done < .repos.tsv
}

queue(){
  local pkg url ref package_count
  sort -u "$OUT/.packages" -o "$OUT/.packages"
  package_count=$(wc -l < "$OUT/.packages" | tr -d '[:space:]')

  if [[ "$package_count" -eq 0 ]]; then
    local_specs_available && { log 'No downloaded packages queued; builder will queue local layered specs per target'; return 0; }
    die 'no packages found from GitHub or local layered specs'
  fi

  log "Final package declarations: $package_count packages"
  sed 's/^/  /' "$OUT/.packages" | tee -a "$LOG" >&2

  git -C "$OUT" init -q
  git -C "$OUT" add .
  git -C "$OUT" -c user.name=builder -c user.email=builder@example.invalid commit --allow-empty -qm specs

  url="file://$PWD/$OUT"
  ref=$(git -C "$OUT" rev-parse HEAD)
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    log "Declare package: $pkg"
    package-build-queue add --package "$pkg" --clone-url "$url" --ref "$ref" --subdir "$pkg" --spec "$pkg.spec"
  done < "$OUT/.packages"
}

main(){ need; init; report_local_specs; discover; fetch_all; queue; }
main "$@"
