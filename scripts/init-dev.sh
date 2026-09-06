#!/bin/bash
# Initialize MAYOTIX OS development environment
#
# Run this after cloning to set up Git hooks, dependencies, and development tools

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Check if running in project root
if [[ ! -f "$PROJECT_ROOT/.gitignore" ]]; then
    log_error "Not in project root. Run from MAYOTIX OS directory."
fi

log_info "Initializing MAYOTIX OS development environment..."

# Install Git hooks
setup_git_hooks() {
    log_info "Setting up Git hooks..."

    mkdir -p "$PROJECT_ROOT/.git/hooks"

    # Pre-commit hook: check for secrets
    cat > "$PROJECT_ROOT/.git/hooks/pre-commit" <<'EOF'
#!/bin/bash
set -euo pipefail

# Check for common secret patterns
patterns=(
    "PRIVATE KEY"
    "-----BEGIN"
    "api_key.*="
    "password.*="
    "secret.*="
    "AWS_SECRET"
)

for pattern in "${patterns[@]}"; do
    if git diff --cached | grep -i "$pattern" 2>/dev/null; then
        echo "❌ Pre-commit hook: Found potential secret in staged files"
        echo "   Pattern: $pattern"
        echo "   Commit aborted to prevent secret leakage"
        exit 1
    fi
done

echo "✓ Pre-commit security check passed"
EOF

    chmod +x "$PROJECT_ROOT/.git/hooks/pre-commit"
    log_success "Git hooks installed"
}

# Initialize directories
setup_directories() {
    log_info "Ensuring all directories exist..."

    directories=(
        "build"
        "build/{iso,root,boot,efi}"
        "tests/results"
        "docs/build"
    )

    for dir in "${directories[@]}"; do
        mkdir -p "$PROJECT_ROOT/$dir"
    done

    log_success "Directories initialized"
}

# Create local development config
setup_local_config() {
    log_info "Creating local development configuration..."

    cat > "$PROJECT_ROOT/.env.local" <<'EOF'
# Local development environment
# This file is NOT committed to Git

# Build configuration
BUILD_QUICK=0
BUILD_DEBUG=0

# SELinux
SELINUX_MODE=enforcing

# Security
ENABLE_AUDIT=1
ENABLE_FIREWALL=1

# Development
RUST_LOG=debug
PYTHON_LOG_LEVEL=INFO
EOF

    log_success "Local config created (.env.local)"
}

# Create helper scripts
setup_helper_scripts() {
    log_info "Creating helper scripts..."

    # Quick build script
    cat > "$PROJECT_ROOT/scripts/quick-build.sh" <<'EOF'
#!/bin/bash
# Quick build for development (skips reproducibility checks)
set -euo pipefail
exec "$(dirname "$0")/build-iso.sh" --quick "$@"
EOF

    # Quick test script
    cat > "$PROJECT_ROOT/scripts/quick-test.sh" <<'EOF'
#!/bin/bash
# Quick test run
set -euo pipefail
cd "$(dirname "$0")/.."
pytest tests/unit/ -v
EOF

    chmod +x "$PROJECT_ROOT/scripts/quick-build.sh" "$PROJECT_ROOT/scripts/quick-test.sh"
    log_success "Helper scripts created"
}

# Print next steps
print_next_steps() {
    cat <<EOF

${GREEN}═════════════════════════════════════════════════════${NC}
${GREEN}MAYOTIX OS Development Environment Ready!${NC}
${GREEN}═════════════════════════════════════════════════════${NC}

${BLUE}Next steps:${NC}

1. ${YELLOW}Read the documentation${NC}
   cat MAYOTIX_ARCHITECTURE.md  # Full technical overview
   cat BUILD.md                 # Build instructions
   cat DEVELOPMENT.md           # Development workflow

2. ${YELLOW}Try a quick build${NC}
   ./scripts/quick-build.sh

3. ${YELLOW}Run tests${NC}
   ./scripts/quick-test.sh

4. ${YELLOW}Check security${NC}
   ./scripts/security-check.sh

${BLUE}Useful commands:${NC}

   ./scripts/build-iso.sh                # Full build (reproducible)
   ./scripts/build-iso.sh --quick        # Quick build (dev)
   ./scripts/test.sh                     # Run all tests
   ./scripts/security-check.sh           # Security verification

${BLUE}Git workflow:${NC}

   git checkout -b feature/my-feature
   # Make changes...
   git add .
   git commit -m "feat: description"
   # Push and open PR

${BLUE}Documentation:${NC}

   MAYOTIX_ARCHITECTURE.md   — Complete technical design
   SECURITY.md               — Security model & disclosure
   BUILD.md                  — Building from source
   DEVELOPMENT.md            — Development guide
   CONTRIBUTING.md           — Contribution guidelines

${BLUE}Security:${NC}

   Pre-commit hook activated: checks for secrets
   Run: ./scripts/security-check.sh before commits

${GREEN}═════════════════════════════════════════════════════${NC}

Questions? See DEVELOPMENT.md or CONTRIBUTING.md

Happy coding! 🚀

EOF
}

# Main
main() {
    setup_git_hooks
    setup_directories
    setup_local_config
    setup_helper_scripts
    print_next_steps

    log_success "Environment setup complete"
}

main "$@"
