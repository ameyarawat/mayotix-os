# Development Guide

## Getting Started

### 1. Set Up Development Environment

```bash
# Clone and enter directory
git clone https://github.com/mayotix/mayotix-os.git
cd mayotix-os

# Create virtual environment (Python tools)
python3 -m venv venv
source venv/bin/activate  # or: . venv/bin/activate on Windows

# Install development dependencies
pip install -r requirements-dev.txt
```

### 2. Install Pre-commit Hooks

```bash
# Install hooks that run before each commit
pre-commit install

# This will:
# - Check for secrets
# - Lint shell scripts
# - Validate JSON/YAML
# - Check code style
```

## Project Structure

```
mayotix-os/
├── boot/                  — Bootloader & kernel configs
├── desktop/               — GNOME customization
├── services/              — Systemd units & daemons
├── cli/                   — MAYOTIX CLI tool
├── installer/             — Installation scripts
├── labs/                  — Lab environment setup
├── security/              — SELinux policies, audit rules
├── packages/              — RPM specs, package patches
├── tests/                 — Test suite
├── tools/                 — Build automation
├── scripts/               — Utility scripts
└── docs/                  — Documentation
```

## Development Workflow

### Making Changes

1. **Create a feature branch**

```bash
git checkout -b feature/my-feature
```

2. **Make your changes**

```bash
# Edit files
nano path/to/file

# Test your changes
./scripts/test.sh

# Check code quality
./scripts/lint.sh
```

3. **Commit with clear message**

```bash
git add .
git commit -m "Add feature: description"

# Format: 
# - feature: new functionality
# - fix: bug fix
# - security: security improvement
# - docs: documentation
# - ci: CI/CD changes
```

4. **Push to your fork**

```bash
git push origin feature/my-feature
```

5. **Open a pull request**

- Provide clear description
- Link any related issues
- Ensure tests pass

### Code Standards

#### Python

```bash
# Format code
black cli/ services/

# Type checking
mypy cli/ services/

# Linting
pylint cli/ services/

# Testing
pytest tests/
```

#### Shell Scripts

```bash
# Check syntax
shellcheck scripts/*.sh

# Format
shfmt -i 2 -w scripts/*.sh
```

#### C/C++ (if used)

```bash
# Format
clang-format -i src/*.c

# Static analysis
cppcheck src/
```

### Running Tests

```bash
# Run all tests
./scripts/test.sh

# Run specific test
./scripts/test.sh tests/test_cli.py

# With coverage
coverage run -m pytest
coverage report
coverage html  # generates htmlcov/index.html
```

### Build ISO for Testing

```bash
# Quick build (no reproducibility checks)
./scripts/build-iso.sh --quick

# Full build
./scripts/build-iso.sh

# Test in QEMU
./scripts/test-boot.sh mayotix-os-*.iso
```

## Working on Specific Components

### Desktop Environment (GNOME)

Files: `desktop/`

```bash
# Edit GNOME shell theme
nano desktop/gnome-shell/gnome-shell.css

# Edit GTK theme
nano desktop/theme/gtk.css

# Edit icon set
# Icons in: desktop/theme/icons/

# Test theme in GNOME (if running locally)
# Copy desktop/ to ~/.local/share/gnome-shell/
# Kill shell: killall -9 gnome-shell
# Restart: press Alt+F2, type 'r', press Enter
```

### CLI Tool

Files: `cli/mayotix/`

```bash
# Install in development mode
pip install -e cli/

# Run commands
mayotix --help
mayotix status

# Debug with verbose output
mayotix --debug status

# Test CLI parsing
pytest tests/test_cli.py -v
```

### Systemd Services

Files: `services/*.service`

```bash
# Check service file syntax
systemd-analyze verify services/mayotix-security.service

# Install service for testing
sudo cp services/mayotix-security.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start mayotix-security
sudo systemctl status mayotix-security

# View logs
journalctl -u mayotix-security -f
```

### SELinux Policies

Files: `security/selinux/`

```bash
# Compile policy
cd security/selinux
make

# Check for syntax errors
checkmodule -M -m mayotix.te

# Load policy
sudo semodule -i mayotix.pp

# View audit violations
sudo grep "AVC" /var/log/audit/audit.log
```

## Security Development

### Before Each Commit

```bash
# Scan for secrets
./scripts/security-check.sh --scan-modified

# Expected: No secrets found

# Check for insecure patterns
grep -r "shell=True" --include="*.py" .
grep -r "eval(" --include="*.py" .
grep -r "exec(" --include="*.py" .
# Expected: No results
```

### Testing Security

```bash
# Run security tests
./scripts/test-security.sh

# Fuzz test CLI argument parsing
./tests/fuzz/cli-fuzz.sh

# Check for privilege escalation
./tests/security/privesc-test.sh
```

## Documentation

### Adding New Features

Create documentation:

1. Update `README.md` with overview
2. Add section to `MAYOTIX_ARCHITECTURE.md` if architectural
3. Create `docs/feature-name.md` with usage guide
4. Add CLI help text
5. Update `CHANGELOG.md`

### Code Comments

```python
# Good: explains WHY, not WHAT
def validate_partition_size(size):
    # Minimum partition size is 2GB to leave room for system
    # and logs. USB installations may go lower but are experimental.
    if size < 2 * 1024 * 1024 * 1024:
        raise ValueError("Partition too small")

# Bad: restates code
def validate_partition_size(size):
    if size < 2 * 1024 * 1024 * 1024:  # Check if size is less than 2GB
        raise ValueError("Partition too small")
```

## Debugging

### QEMU Boot Issues

```bash
# Boot with serial console output
qemu-system-x86_64 \
  -cdrom mayotix-os-*.iso \
  -m 4G \
  -nographic \
  -serial mon:stdio

# In GRUB, press 'e' to edit, add: debug console=ttyS0
```

### SELinux Denials

```bash
# View all AVC denials
sudo journalctl -g "AVC"

# Set to permissive temporarily to collect denials
sudo semanage permissive -a mayotix_t

# Generate policy from denials
audit2allow -a -M mayotix_new
```

### Systemd Service Debugging

```bash
# Increase service verbosity
sudo systemctl edit mayotix-security

# Add:
[Service]
Environment="RUST_LOG=debug"

# Restart and view logs
sudo systemctl restart mayotix-security
journalctl -u mayotix-security -f
```

## Performance Profiling

```bash
# Profile boot time
systemd-analyze
systemd-analyze blame  # Services taking longest
systemd-analyze critical-chain

# Profile CLI tool
python -m cProfile -s cumulative -m mayotix status

# Memory usage
/usr/bin/time -v mayotix status
```

## Contributing

See `CONTRIBUTING.md` for:

- Code of Conduct
- Pull Request Process
- Commit Message Format
- Testing Requirements
- Security Guidelines

## Getting Help

- **Questions:** GitHub Discussions
- **Issues:** GitHub Issues (non-security)
- **Security:** security@mayotix.os (see SECURITY.md)
- **Documentation:** https://mayotix.os/docs

---

**Last Updated:** 2026-09-06  
**MAYOTIX OS Development Team**
