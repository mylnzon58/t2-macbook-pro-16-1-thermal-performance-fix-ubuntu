#!/usr/bin/env bash
# ==============================================================================
# 1-Step GitHub Login, Public Repository Creation & GitHub Pages Deployment
# Author: mylnzon58 <mylnzon58@gmail.com>
# ==============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO_DIR}"

REPO_NAME="t2-macbook-pro-16-1-thermal-performance-fix-ubuntu"
DESC="MacBook Pro 16,1 (2019, A2141) High-Performance Thermal & Per-Core Asymmetric Kernel Tuning for Ubuntu 24.04 LTS"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

export PATH="${HOME}/.local/bin:/tmp:${PATH}"

echo -e "${CYAN}==> Preparing to publish ${REPO_NAME} to GitHub (mylnzon58@gmail.com)...${NC}"

if ! command -v gh &>/dev/null; then
    echo -e "${YELLOW}[!] Downloading official GitHub CLI (gh) to ~/.local/bin/gh...${NC}"
    mkdir -p "${HOME}/.local/bin"
    GH_VER="2.62.0"
    curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VER}/gh_${GH_VER}_linux_amd64.tar.gz" -o /tmp/gh.tar.gz
    tar -xzf /tmp/gh.tar.gz -C /tmp
    cp -f "/tmp/gh_${GH_VER}_linux_amd64/bin/gh" "${HOME}/.local/bin/gh"
    chmod +x "${HOME}/.local/bin/gh"
    rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VER}_linux_amd64"
    echo -e "${GREEN}[✓] Installed GitHub CLI to ~/.local/bin/gh${NC}"
fi

if ! gh auth status &>/dev/null; then
    echo -e "${CYAN}==> Opening browser for GitHub authentication (mylnzon58@gmail.com)...${NC}"
    printf '\n' | gh auth login -h github.com -p https -w
fi

GH_USER="$(gh api user -q .login)"
echo -e "${GREEN}[✓] Authenticated as GitHub user: @${GH_USER} (mylnzon58@gmail.com)${NC}"

git config user.name "${GH_USER}"
git config user.email "mylnzon58@gmail.com"
gh auth setup-git

if [[ "${GH_USER}" != "mylnzon58" ]]; then
    sed -i "s|github.com/mylnzon58|github.com/${GH_USER}|g" README.md docs/index.html 2>/dev/null || true
    sed -i "s|mylnzon58.github.io|${GH_USER}.github.io|g" docs/robots.txt docs/sitemap.xml 2>/dev/null || true
fi

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    git init -b main
    git add .
    git commit -m "feat: initial commit - MacBook Pro 16,1 asymmetric thermal tuning and docs"
else
    git add .
    git commit -m "feat: update thermal tuning and docs" || true
fi

if gh repo view "${GH_USER}/${REPO_NAME}" &>/dev/null; then
    echo -e "${CYAN}[i] Repository ${GH_USER}/${REPO_NAME} already exists. Pushing main...${NC}"
    git remote set-url origin "https://github.com/${GH_USER}/${REPO_NAME}.git" 2>/dev/null || \
        git remote add origin "https://github.com/${GH_USER}/${REPO_NAME}.git"
    git push -u origin main --force
else
    echo -e "${CYAN}==> Creating public repository ${GH_USER}/${REPO_NAME} and pushing commits...${NC}"
    gh repo create "${REPO_NAME}" --public --source=. --remote=origin --description "${DESC}" --push
fi

echo -e "${CYAN}==> Setting GitHub SEO repository topics & homepage...${NC}"
gh repo edit "${GH_USER}/${REPO_NAME}" \
    --homepage "https://${GH_USER}.github.io/${REPO_NAME}/" \
    --add-topic "macbook-pro" \
    --add-topic "macbookpro16-1" \
    --add-topic "a2141" \
    --add-topic "apple-t2" \
    --add-topic "thermal-throttling" \
    --add-topic "intel-pstate" \
    --add-topic "ubuntu-24-04" \
    --add-topic "linux-kernel" \
    --add-topic "undervolt" \
    --add-topic "amdgpu" || true

echo -e "${CYAN}==> Activating GitHub Pages from main:/docs...${NC}"
gh api -X POST "repos/${GH_USER}/${REPO_NAME}/pages" \
    -f "source[branch]=main" -f "source[path]=/docs" 2>/dev/null || \
gh api -X PUT "repos/${GH_USER}/${REPO_NAME}/pages" \
    -f "source[branch]=main" -f "source[path]=/docs" 2>/dev/null || true

echo -e "\n${GREEN}======================================================================${NC}"
echo -e "${GREEN}[✓] Public Repository:${NC} https://github.com/${GH_USER}/${REPO_NAME}"
echo -e "${GREEN}[✓] Live Landing Page:${NC} https://${GH_USER}.github.io/${REPO_NAME}/"
echo -e "${GREEN}======================================================================${NC}"
