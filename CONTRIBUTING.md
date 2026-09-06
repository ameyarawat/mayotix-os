# Contributing to MAYOTIX OS

Thank you for your interest in contributing to MAYOTIX OS!

We welcome contributions from security researchers, developers, designers, and community members. This document outlines our contribution process and expectations.

## Code of Conduct

All contributors are expected to uphold our Code of Conduct:

- Be respectful and inclusive
- Assume good intent
- Avoid harassment, discrimination, or hostile behavior
- Report violations to conduct@mayotix.os

## Getting Started

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Follow the development guide: [DEVELOPMENT.md](DEVELOPMENT.md)
4. Make your changes
5. Run tests: `./scripts/test.sh`
6. Run security checks: `./scripts/security-check.sh`
7. Commit with clear messages (see below)
8. Push to your fork and open a pull request

## Commit Message Format

Use clear, descriptive commit messages:

```
<type>: <subject>

<body (optional)>

<footer (optional)>
```

**Types:**
- `feat:` — new feature
- `fix:` — bug fix
- `security:` — security improvement or fix
- `docs:` — documentation
- `style:` — code style (formatting, etc.)
- `refactor:` — code refactoring
- `test:` — test additions/changes
- `ci:` — CI/CD changes
- `perf:` — performance improvement

**Examples:**

```
security: validate CLI arguments to prevent command injection

Prevent shell metacharacters from reaching subprocess execution.
Add strict allowlist for command names, parameters validated as strings.

Fixes #42
```

```
feat: add firewall rule management to mayotix CLI

Add `mayotix firewall list`, `mayotix firewall add`, `mayotix firewall delete`
commands to manage firewall rules programmatically.
```

## Pull Request Process

1. **Title and Description**
   - Title: clear, descriptive, under 70 characters
   - Description: explain what, why, and how
   - Link related issues: `Fixes #123`, `Relates to #456`

2. **Testing**
   - Add tests for new functionality
   - Ensure all tests pass: `./scripts/test.sh`
   - Test on multiple systems if applicable

3. **Security Review**
   - Run security checks: `./scripts/security-check.sh`
   - If you added code that handles:
     - User input → validate and escape
     - Privileged operations → use polkit/sudo appropriately
     - Network communication → use TLS
     - Cryptography → use established libraries
     - Temporary files → use secure temp directory
   - Explain security implications in PR description

4. **Documentation**
   - Update relevant documentation
   - Add CLI help text if applicable
   - Update CHANGELOG.md

5. **Review and Merge**
   - Minimum 2 approvals required
   - All tests must pass
   - No critical security findings
   - Maintainer merges when ready

## Areas to Contribute

### High Priority

- Security audits (see SECURITY.md for reporting)
- Performance optimization
- Hardening systemd services
- SELinux policy refinement
- Testing (especially security tests)
- Documentation

### Medium Priority

- Desktop theme refinement
- CLI improvements
- Installer enhancement
- Lab environment templates
- Developer environment setup

### Lower Priority (Phase 2+)

- Gaming support
- Developer modes
- Advanced security tools
- Visual polish

## Testing Guidelines

### Unit Tests

```python
# tests/test_cli.py
import pytest
from mayotix.cli import parse_args

def test_cli_parse_valid_command():
    args = parse_args(['mayotix', 'status'])
    assert args.command == 'status'

def test_cli_parse_rejects_injection():
    # Ensure command injection attempts are blocked
    with pytest.raises(ValueError):
        parse_args(['mayotix', 'status; rm -rf /'])
```

### Integration Tests

```bash
# tests/integration/test_boot.sh
# Test actual boot in QEMU
set -euo pipefail

ISO="mayotix-os-*.iso"
TIMEOUT=120

qemu-system-x86_64 \
  -cdrom "$ISO" \
  -m 4G \
  -enable-kvm \
  -nographic \
  -serial mon:stdio \
  -timeout "$TIMEOUT" \
  | grep -q "MAYOTIX OS" && echo "✓ Boot test passed"
```

### Security Tests

```bash
# tests/security/test_permissions.sh
# Verify critical file permissions

check_permission() {
    local file=$1
    local expected=$2
    local actual=$(stat -c '%a' "$file" 2>/dev/null)
    [[ "$actual" == "$expected" ]] || exit 1
}

check_permission "/etc/shadow" "640"
check_permission "/root" "700"
echo "✓ Permissions test passed"
```

## Code Style

### Python

```bash
# Format with black
black cli/ services/

# Type check with mypy
mypy cli/ services/

# Lint with pylint
pylint cli/ services/

# Test with pytest
pytest tests/ -v
```

### Shell

```bash
# Check syntax
shellcheck scripts/*.sh

# Format with shfmt
shfmt -i 2 -w scripts/*.sh
```

### Security Requirements

1. **Never use `shell=True` in subprocess calls**
   ```python
   # ✗ WRONG
   subprocess.run(f"mayotix {cmd}", shell=True)

   # ✓ RIGHT
   subprocess.run(["mayotix", cmd])
   ```

2. **Validate all user input**
   ```python
   # ✓ RIGHT
   def validate_firewall_rule(rule):
       if not isinstance(rule, str):
           raise ValueError("Invalid rule type")
       if len(rule) > 255:
           raise ValueError("Rule too long")
       # Allowlist pattern validation
       if not re.match(r'^[a-zA-Z0-9_-]+$', rule):
           raise ValueError("Invalid rule format")
       return rule
   ```

3. **Use parameterized queries**
   ```python
   # ✗ WRONG
   query = f"SELECT * FROM audit WHERE user = '{username}'"

   # ✓ RIGHT
   query = "SELECT * FROM audit WHERE user = ?"
   cursor.execute(query, (username,))
   ```

4. **Escape output when displaying**
   ```python
   # ✗ WRONG
   print(user_input)  # May contain escape codes

   # ✓ RIGHT
   print(shlex.quote(user_input))
   ```

5. **No hardcoded secrets**
   - Never commit API keys, passwords, or signing keys
   - Use environment variables or secure vaults
   - Pre-commit hooks will scan for secrets

## Documentation Standards

### Code Comments

```python
# Explain WHY, not WHAT
# WRONG:
total = 0  # Set total to 0

# RIGHT:
# Initialize to 0 before accumulating entries
total = 0
```

### Function Documentation

```python
def verify_iso_signature(iso_path: str, sig_path: str) -> bool:
    """
    Verify ISO image signature using GPG.

    Args:
        iso_path: Path to ISO file
        sig_path: Path to detached signature file

    Returns:
        True if signature is valid, False otherwise

    Raises:
        FileNotFoundError: If ISO or signature file not found
        GPGError: If GPG verification fails

    Security:
        - Signature must be created with MAYOTIX release key
        - Uses strict GPG verification (trust-model: direct)
    """
```

### README and Docs

- Keep language simple and clear
- Use examples
- Document assumptions
- Explain security implications
- Link to related docs

## Security Considerations

### Before Submitting

- [ ] No secrets committed (API keys, passwords, private keys)
- [ ] All user input validated
- [ ] No unsafe subprocess execution (shell=True)
- [ ] No hardcoded credentials
- [ ] Security tests added
- [ ] No disabled security controls (SELinux, firewall)
- [ ] Dependencies audited
- [ ] No new privileges required unnecessarily

### Report Security Issues

**DO NOT** open issues for security vulnerabilities.

See [SECURITY.md](SECURITY.md) for responsible disclosure.

## Questions?

- **Issues:** https://github.com/mayotix/mayotix-os/issues
- **Discussions:** https://github.com/mayotix/mayotix-os/discussions
- **Security:** security@mayotix.os (see SECURITY.md)

---

Thank you for contributing to MAYOTIX OS!

**Last Updated:** 2026-09-06
