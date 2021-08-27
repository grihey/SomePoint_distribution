#!/bin/bash

SCRIPTS=(check-commit.sh commit-msg)
SUBREPOS=(docker linux buildroot)

set -e

if [ ! -d .git/hooks ]; then
    echo ".git/hooks not found" >&2
    exit 1
fi

# Get repo url with usernames and ports etc.
REPO="$(git remote get-url --all origin)"
REPO="${REPO%%sp_distro}"
REPO+="misc"

# Fetch scripts from Phone/misc/githooks
for S in "${SCRIPTS[@]}"; do
    echo "Fetching ${S}"
    git archive "--remote=${REPO}" HEAD "githooks/${S}" | tar xO > ".git/hooks/${S}"
    chmod a+x ".git/hooks/${S}"
done

# If freshly cloned main repo, initialize submodules
if [ ! -d .git/modules ]; then
    git submodule init
    git submodule update -f
fi

# Link main repo hooks to our subrepos
for R in "${SUBREPOS[@]}"; do
    if [ -d ".git/modules/${R}" ]; then
        echo "Removing .git/modules/${R}/hooks"
        rm -rf ".git/modules/${R}/hooks"
        echo "Linking .git/modules/${R}/hooks to .git/hooks"
        ln -s ../../hooks ".git/modules/${R}/hooks"
    else
        echo ".git/modules/${R} not found!" >&2
        exit 1
    fi
done
