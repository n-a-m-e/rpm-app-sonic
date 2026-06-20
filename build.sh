#!/usr/bin/env bash
set -euo pipefail

ORG=${ORG:-OpenMandrivaAssociation}
SPECS_DIR=${SPECS_DIR:-specs}
TERMS=${TERMS:-"sonic silver"}
BRANCHES=${BRANCHES:-"master main rolling"}
BLACKLIST=${BLACKLIST:-"sonic sonic-visualiser python-silvercity rust-silver"}

log(){ printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die(){ log "ERROR: $*"; exit 1; }
contains(){ case " $1 " in *" $2 "*) return 0;; *) return 1;; esac; }

rm -rf specs-tmp .repos.tsv
mkdir -p specs-tmp "$SPECS_DIR"
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
  log "Fetching spec: $repo"
  ok=0

  for branch in $BRANCHES; do
    rm -rf "specs-tmp/$repo"
    mkdir -p "specs-tmp/$repo"

    if curl -fsSL --retry 3 --retry-delay 2 "https://codeload.github.com/$full/tar.gz/$branch" \
      | tar -xz -C "specs-tmp/$repo" --strip-components=1 \
      && [[ -f "specs-tmp/$repo/$repo.spec" ]]; then
      cp "specs-tmp/$repo/$repo.spec" "$SPECS_DIR/$repo.spec"
      ok=1
      break
    fi
  done

  [[ "$ok" == 1 ]] || die "missing root spec: $repo"
done < .repos.tsv

log "Created $(find "$SPECS_DIR" -maxdepth 1 -name '*.spec' | wc -l) specs in $SPECS_DIR/"
