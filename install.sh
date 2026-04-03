#!/usr/bin/env bash
set -euo pipefail

# Claude SEO Installer
# Wraps everything in main() to prevent partial execution on network failure

main() {
    SKILL_DIR="${HOME}/.claude/skills/seo"
    AGENT_DIR="${HOME}/.claude/agents"
    REPO_URL="https://github.com/AgriciDaniel/claude-seo"
    # Pin to a specific release tag to prevent silent updates from main.
    # Override: CLAUDE_SEO_TAG=main bash install.sh
    REPO_TAG="${CLAUDE_SEO_TAG:-v1.7.2}"

    echo "════════════════════════════════════════"
    echo "║   Claude SEO - Installer             ║"
    echo "║   Claude Code SEO Skill              ║"
    echo "════════════════════════════════════════"
    echo ""

    # Check prerequisites
    command -v python3 >/dev/null 2>&1 || { echo "✗ Python 3 is required but not installed."; exit 1; }
    command -v git >/dev/null 2>&1 || { echo "✗ Git is required but not installed."; exit 1; }

    # Check Python version (3.10+ required)
    PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    PYTHON_OK=$(python3 -c 'import sys; print(1 if sys.version_info >= (3, 10) else 0)')
    if [ "${PYTHON_OK}" = "0" ]; then
        echo "✗ Python 3.10+ is required but ${PYTHON_VERSION} was found."
        exit 1
    fi
    echo "✓ Python ${PYTHON_VERSION} detected"

    # Back up previous installation (preserve .venv)
    BACKUP_DIR=""
    if [ -L "${SKILL_DIR}" ]; then
        # Previous local install left a symlink — just remove it
        rm -f "${SKILL_DIR}"
    elif [ -d "${SKILL_DIR}" ]; then
        BACKUP_DIR=$(mktemp -d)
        # Move everything except .venv to backup
        for item in "${SKILL_DIR}"/*; do
            [ -e "${item}" ] || [ -L "${item}" ] || continue
            [ "$(basename "${item}")" = ".venv" ] && continue
            mv "${item}" "${BACKUP_DIR}/"
        done
        # Also grab dotfiles (except .venv)
        for item in "${SKILL_DIR}"/.[!.]*; do
            [ -e "${item}" ] || [ -L "${item}" ] || continue
            [ "$(basename "${item}")" = ".venv" ] && continue
            mv "${item}" "${BACKUP_DIR}/"
        done
    fi

    # Restore backup on failure, clean up on success
    cleanup() {
        local exit_code=$?
        if [ ${exit_code} -ne 0 ] && [ -n "${BACKUP_DIR}" ] && [ -d "${BACKUP_DIR}" ]; then
            echo "✗ Install failed, restoring previous installation..."
            for item in "${BACKUP_DIR}"/*; do
                [ -e "${item}" ] || [ -L "${item}" ] || continue
                mv "${item}" "${SKILL_DIR}/"
            done
            for item in "${BACKUP_DIR}"/.[!.]*; do
                [ -e "${item}" ] || [ -L "${item}" ] || continue
                mv "${item}" "${SKILL_DIR}/"
            done
        fi
        [ -n "${BACKUP_DIR}" ] && rm -rf "${BACKUP_DIR}" || true
        [ -n "${TEMP_DIR:-}" ] && rm -rf "${TEMP_DIR}" || true
    }
    trap cleanup EXIT

    # Create directories
    mkdir -p "${SKILL_DIR}"
    mkdir -p "${AGENT_DIR}"

    # Detect if running from a local git repo checkout
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LOCAL_REPO=""
    if [ -f "${SCRIPT_DIR}/skills/seo/SKILL.md" ] && [ -f "${SCRIPT_DIR}/requirements.txt" ]; then
        echo "✓ Local repo detected at ${SCRIPT_DIR}, installing via symlinks"
        LOCAL_REPO="${SCRIPT_DIR}"
        SOURCE_DIR="${SCRIPT_DIR}"
    else
        TEMP_DIR=$(mktemp -d)
        echo "↓ Downloading Claude SEO (${REPO_TAG})..."
        git clone --depth 1 --branch "${REPO_TAG}" "${REPO_URL}" "${TEMP_DIR}/claude-seo" 2>/dev/null
        SOURCE_DIR="${TEMP_DIR}/claude-seo"
    fi

    # Helper: symlink (local) or copy (remote)
    install_item() {
        local src="$1" dst="$2"
        # Remove stale symlinks so cp doesn't write through them into the repo
        [ -L "${dst}" ] && rm -f "${dst}"
        if [ -n "${LOCAL_REPO}" ]; then
            ln -sf "${src}" "${dst}"
        else
            cp -rf "${src}" "${dst}"
        fi
    }

    # Install skill files
    echo "→ Installing skill files..."
    for item in "${SOURCE_DIR}/skills/seo/"*; do
        install_item "${item}" "${SKILL_DIR}/$(basename "${item}")"
    done

    # Install sub-skills (skip seo — it's SKILL_DIR, handled above)
    if [ -d "${SOURCE_DIR}/skills" ]; then
        for skill_dir in "${SOURCE_DIR}/skills"/*/; do
            skill_name=$(basename "${skill_dir}")
            [ "${skill_name}" = "seo" ] && continue
            target="${HOME}/.claude/skills/${skill_name}"
            # Remove stale symlinks so cp doesn't write through them
            [ -L "${target}" ] && rm -f "${target}"
            if [ -n "${LOCAL_REPO}" ]; then
                rm -rf "${target}" 2>/dev/null || true
                ln -sf "${skill_dir%/}" "${target}"
            else
                mkdir -p "${target}"
                cp -rf "${skill_dir}"* "${target}/"
            fi
        done
    fi

    # Install schema templates
    if [ -d "${SOURCE_DIR}/schema" ]; then
        install_item "${SOURCE_DIR}/schema" "${SKILL_DIR}/schema"
    fi

    # Install reference docs
    if [ -d "${SOURCE_DIR}/pdf" ]; then
        install_item "${SOURCE_DIR}/pdf" "${SKILL_DIR}/pdf"
    fi

    # Install agents
    echo "→ Installing subagents..."
    for agent in "${SOURCE_DIR}/agents/"*.md; do
        [ -f "${agent}" ] || continue
        install_item "${agent}" "${AGENT_DIR}/$(basename "${agent}")"
    done

    # Install shared scripts
    if [ -d "${SOURCE_DIR}/scripts" ]; then
        install_item "${SOURCE_DIR}/scripts" "${SKILL_DIR}/scripts"
    fi

    # Install hooks
    if [ -d "${SOURCE_DIR}/hooks" ]; then
        install_item "${SOURCE_DIR}/hooks" "${SKILL_DIR}/hooks"
    fi

    # Install extensions (optional add-ons: dataforseo, banana)
    if [ -d "${SOURCE_DIR}/extensions" ]; then
        echo "=> Installing extensions..."
        for ext_dir in "${SOURCE_DIR}/extensions"/*/; do
            [ -d "${ext_dir}" ] || continue
            ext_name=$(basename "${ext_dir}")
            # Extension skills
            if [ -d "${ext_dir}skills" ]; then
                for ext_skill in "${ext_dir}skills"/*/; do
                    [ -d "${ext_skill}" ] || continue
                    ext_skill_name=$(basename "${ext_skill}")
                    target="${HOME}/.claude/skills/${ext_skill_name}"
                    [ -L "${target}" ] && rm -f "${target}"
                    if [ -n "${LOCAL_REPO}" ]; then
                        rm -rf "${target}" 2>/dev/null || true
                        ln -sf "${ext_skill%/}" "${target}"
                    else
                        mkdir -p "${target}"
                        cp -rf "${ext_skill}"* "${target}/"
                    fi
                done
            fi
            # Extension agents
            if [ -d "${ext_dir}agents" ]; then
                for agent in "${ext_dir}agents/"*.md; do
                    [ -f "${agent}" ] || continue
                    install_item "${agent}" "${AGENT_DIR}/$(basename "${agent}")"
                done
            fi
            # Extension references
            if [ -d "${ext_dir}references" ]; then
                if [ -n "${LOCAL_REPO}" ]; then
                    mkdir -p "${SKILL_DIR}/extensions/${ext_name}"
                    install_item "${ext_dir}references" "${SKILL_DIR}/extensions/${ext_name}/references"
                else
                    mkdir -p "${SKILL_DIR}/extensions/${ext_name}/references"
                    cp -rf "${ext_dir}references/"* "${SKILL_DIR}/extensions/${ext_name}/references/"
                fi
            fi
            # Extension scripts
            if [ -d "${ext_dir}scripts" ]; then
                if [ -n "${LOCAL_REPO}" ]; then
                    mkdir -p "${SKILL_DIR}/extensions/${ext_name}"
                    install_item "${ext_dir}scripts" "${SKILL_DIR}/extensions/${ext_name}/scripts"
                else
                    mkdir -p "${SKILL_DIR}/extensions/${ext_name}/scripts"
                    cp -rf "${ext_dir}scripts/"* "${SKILL_DIR}/extensions/${ext_name}/scripts/"
                fi
            fi
        done
    fi

    # Make requirements.txt available in skill dir
    install_item "${SOURCE_DIR}/requirements.txt" "${SKILL_DIR}/requirements.txt"

    # Install Python dependencies (venv preferred, --user fallback)
    echo "→ Installing Python dependencies..."
    VENV_DIR="${SKILL_DIR}/.venv"
    if ! python3 -m venv "${VENV_DIR}" 2>/dev/null; then
        echo "✗ Failed to create venv at ${VENV_DIR}. Ensure python3-venv is installed."
        exit 1
    fi
    "${VENV_DIR}/bin/pip" install --quiet -r "${SOURCE_DIR}/requirements.txt"
    echo "  ✓ Installed in venv at ${VENV_DIR}"

    # Optional: Install Playwright browsers (for screenshot analysis)
    echo "→ Installing Playwright browsers (optional, for visual analysis)..."
    "${VENV_DIR}/bin/python" -m playwright install chromium 2>/dev/null || \
        echo "  ⚠  Playwright install failed. Visual analysis will use WebFetch fallback."

    echo ""
    echo "✓ Claude SEO installed successfully!"
    echo ""
    echo "Usage:"
    echo "  1. Start Claude Code:  claude"
    echo "  2. Run commands:       /seo audit https://example.com"
    echo ""
    echo "Python deps location: ${SKILL_DIR}/requirements.txt"
    echo "To uninstall: curl -fsSL ${REPO_URL}/raw/main/uninstall.sh | bash"
}

main "$@"
