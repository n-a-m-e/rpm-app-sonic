#!/usr/bin/env bash
set -euo pipefail

ORG=${ORG:-OpenMandrivaAssociation}
TERMS=${TERMS:-"sonic silver"}
BRANCHES=${BRANCHES:-"master main rolling"}
BLACKLIST=${BLACKLIST:-"sonic sonic-visualiser python-silvercity rust-silver"}
FETCH_DIR=${FETCH_DIR:-specs-tmp}

log(){ printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die(){ log "ERROR: $*"; exit 1; }
contains(){ case " $1 " in *" $2 "*) return 0;; *) return 1;; esac; }

rm -rf "$FETCH_DIR" .repos.tsv
mkdir -p "$FETCH_DIR"
: > .repos.tsv

for term in $TERMS; do
  log "Discovering repos matching: $term"
  curl -fsSL --retry 3 --retry-delay 2 \
    -H 'Accept: application/vnd.github+json' \
    -H 'User-Agent: sonicde-build-specs' \
    "https://api.github.com/search/repositories?q=${term}%20in:name,description+org:${ORG}&per_page=100" \
  | grep -aoE '"full_name"[[:space:]]*:[[:space:]]*"[^"/]+/[^"/]+"' \
  | sed -E 's/.*"([^"/]+\/[^"/]+)"/\1/' \
  | while read -r full; do
      repo=${full##*/}
      contains "$BLACKLIST" "$repo" || printf '%s\t%s\n' "$repo" "$full"
    done >> .repos.tsv
done

sort -u .repos.tsv -o .repos.tsv
[[ -s .repos.tsv ]] || die "no package repos discovered"

while IFS=$'\t' read -r repo full; do
  log "Fetching package repo: $repo"
  ok=0

  for branch in $BRANCHES; do
    rm -rf "$FETCH_DIR/$repo"
    mkdir -p "$FETCH_DIR/$repo"

    if curl -fsSL --retry 3 --retry-delay 2 "https://codeload.github.com/$full/tar.gz/$branch" \
      | tar -xz -C "$FETCH_DIR/$repo" --strip-components=1 \
      && [[ -f "$FETCH_DIR/$repo/$repo.spec" ]]; then

      rm -rf "$repo"
      mkdir -p "$repo"
      cp -a "$FETCH_DIR/$repo/." "$repo/"

      ok=1
      break
    fi
  done

  [[ "$ok" == 1 ]] || die "missing root spec: $repo"
done < .repos.tsv

log "Created $(find . -mindepth 2 -maxdepth 2 -name '*.spec' -printf '.' | wc -c) package repos"
