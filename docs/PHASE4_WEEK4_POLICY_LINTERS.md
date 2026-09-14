# MAYOTIX OS Phase 4 Week 4: Security-Focused Local CI/CD & Policy Linters

This document outlines the implementation of security-focused local CI/CD and policy linters for MAYOTIX OS. We integrate automated security checks into the developer workflow to prevent unsafe code and configurations from being committed.

---

## Overview

Phase 4 Week 4 focuses on shifting security left by integrating automated checks into the local development workflow. This includes:

- **Git pre-commit hooks** that scan for secrets, lint shell scripts, and validate Containerfiles.
- **SELinux policy linters** that statically analyze policy files for common pitfalls and verify compilation.
- **Local compliance test suite** that validates the presence and correctness of Phase 4 security controls.
- **Documentation** guiding developers on setup, usage, and extension of these tools.

---

## Technical Implementation

### 1. Git Pre-Commit Security Hooks (`.githooks/pre-commit` & `scripts/install-git-hooks.sh`)

The pre-commit hook performs three key checks:

#### Secret Detection
- Scans staged files for patterns indicating private keys, tokens, and credentials (e.g., `BEGIN RSA PRIVATE KEY`, `AIza...`, `xoxb...`).
- Blocks commit if any potential secret is found.

#### Shell Script Linting (ShellCheck)
- Invokes `shellcheck` on all staged `.sh` files.
- Reports warnings and errors; non-zero exit from shellcheck blocks the commit.

#### Containerfile Linting (Hadolint)
- Invokes `hadolint` on all staged `Containerfile` files.
- Reports warnings and errors; non-zero exit from hadolint blocks the commit.

##### Installation
Run `scripts/install-git-hooks.sh` to:
1. Ensure the `.githooks` directory exists.
2. Make the pre-commit hook executable.
3. Configure Git to use `.githooks` as the hooks directory (`git config core.hooksPath .githooks`).

##### Usage
Once installed, the hook runs automatically on `git commit`. To bypass (not recommended), use `git commit --no-verify`.

### 2. SELinux Policy Linter & Verifier (`scripts/lint-selinux-policies.sh`)

This script performs static analysis on SELinux Type Enforcement (`.te`) files to catch common mistakes and verifies that policies compile.

#### Linting Checks
- **Module declaration**: Warns if missing `module` or `policy_module`.
- **Unconfined transitions**: Flags any transition to `unconfined_t`.
- **Wildcard permissions**: Detects use of `*` in permission sets (e.g., `{ read write * }`).
- **Missing require blocks**: Suggests adding a `require` block when external types are used.
- **Permissive domains**: Warns if any domain is set to permissive.

#### Compilation Verification
- Uses `checkmodule` to compile each `.te` file into a `.mod` module.
- Reports success or failure; compilation errors block the script from returning success.

##### Usage
```bash
# Lint all policies
./scripts/lint-selinux-policies.sh

# Lint a specific policy
./scripts/lint-selinux-policies.sh mayotix.te
```

### 3. Local Phase 4 Compliance Test Suite (`scripts/test-phase4-compliance.sh`)

This automated suite validates that the system meets the baseline requirements for Phase 4.

#### Checks Performed
1. **Rootless container sysctl parameters**
   - Verifies `kernel.unprivileged_userns_clone=1` (either in `/proc/sys` or sysctl config).
2. **Signature policy presence**
   - Checks for `/etc/containers/policy.json` and validates JSON (if `jq` is available).
3. **Devbox recipe syntax**
   - Ensures each `Containerfile` in `desktop/dev-environments/recipes/` has a `FROM` instruction and does not set the user to root.
4. **Pre-commit hook installation**
   - Confirms that Git is configured to use `.githooks` and that the pre-commit hook exists and is executable.

##### Usage
```bash
# Run all checks
./scripts/test-phase4-compliance.sh

# Verbose output
./scripts/test-phase4-compliance.sh --verbose
```

### 4. Documentation

This document (`docs/PHASE4_WEEK4_POLICY_LINTERS.md`) serves as the comprehensive guide for Week 4.

---

## Operational Workflow

### Typical Developer Workflow
1. **Setup (one-time)**
   ```bash
   # Install pre-commit hooks
   ./scripts/install-git-hooks.sh

   # Optionally, install ShellCheck and Hadolint if not present
   # (e.g., via package manager: sudo dnf install ShellCheck hadolint)
   ```

2. **Development**
   - Edit files as usual.
   - Before each commit, the pre-commit hook runs automatically.
   - If the hook fails, fix the issues and retry the commit.

3. **Validation (optional, but recommended)**
   ```bash
   # Run the full Phase 4 compliance suite
   ./scripts/test-phase4-compliance.sh
   ```

### Extending the Hooks
To add new checks to the pre-commit hook:
1. Edit `.githooks/pre-commit`.
2. Add your check function (e.g., for YAML linting, JSON validation, etc.).
3. Ensure the function returns a non-zero exit code on failure to block the commit.

---

## Security Properties

| Property                            | Implementation Detail                                                                 |
|-------------------------------------|---------------------------------------------------------------------------------------|
| **Secret Prevention**               | Blocks commits containing patterns matching private keys, tokens, and credentials.    |
| **Shell Script Safety**             | Ensures all shell scripts pass ShellCheck before commit.                              |
| **Containerfile Correctness**       | Validates Containerfiles with Hadolint to prevent common mistakes.                    |
| **SELinux Policy Integrity**        | Lints and verifies SELinux policies to avoid common pitfalls and ensure compilation. |
| **Phase 4 Compliance Assurance**    | Local test suite validates critical sysctl, signature policy, devbox, and hook states.|
| **Local First, CI/CD Ready**        | All checks are designed to run locally and can be easily integrated into CI/CD pipelines. |

---

## Verification Procedures

### 1. Verify Secret Detection
```bash
# Create a test file with a fake private key
echo "-----BEGIN RSA PRIVATE KEY-----" > test-key.txt
git add test-key.txt
git commit -m "Test: should fail"
# Expect: commit fails with error about potential secrets
git reset HEAD test-key.txt && rm test-key.txt
```

### 2. Verify ShellCheck Integration
```bash
# Create a shell script with an error
echo '#!/bin/bash' > bad.sh
echo 'echo $undefined_var' >> bad.sh
git add bad.sh
git commit -m "Test: should fail on ShellCheck"
# Expect: commit fails with ShellCheck output
git reset HEAD bad.sh && rm bad.sh
```

### 3. Verify Hadolint Integration
```bash
# Create a Containerfile with an error (e.g., FROM without a tag)
echo 'FROM alpine' > Dockerfile.test
git add Dockerfile.test
git commit -m "Test: should fail on Hadolint"
# Expect: commit fails with Hadolint warning about missing tag
git reset HEAD Dockerfile.test && rm Dockerfile.test
```

### 4. Verify SELinux Policy Linter
```bash
# Lint an existing policy
./scripts/lint-selinux-policies.sh security/selinux/mayotix.te
# Expect: success or warnings (if any)

# To test a failing lint, you could temporarily edit a policy to add a wildcard permission
```

### 5. Verify Compliance Test Suite
```bash
# Run the suite
./scripts/test-phase4-compliance.sh
# Expect: all checks pass (if the system is properly configured)
```

---

## Maintenance & Updates

### Updating Linting Rules
- **Secret detection**: Adjust the regex in `.githooks/pre-commit` to match new patterns.
- **ShellCheck**: Update via package manager; the hook uses the installed version.
- **Hadolint**: Update via package manager; the hook uses the installed version.
- **SELinux linter**: Edit `scripts/lint-selinux-policies.sh` to add new static analysis checks.

### Updating Compliance Tests
- Edit `scripts/test-phase4-compliance.sh` to add or modify checks as Phase 4 requirements evolve.

### Dependency Management
The hooks and scripts rely on the following tools being available in the PATH:
- `git` (for hooks and compliance)
- `shellcheck` (for shell script linting)
- `hadolint` (for Containerfile linting)
- `checkmodule` (from SELinux policy development package, for SELinux linting)
- `jq` (optional, for JSON validation of signature policy)
- `grep`, `sed`, `awk` (standard POSIX tools)

If any of these are missing, the scripts will skip the corresponding check and issue a warning.

---

## Reference Architecture

```
Developer Workflow
│
├── Edit Files
│
├── git add <files>
│
└── git commit
     │
     ├──→ .githooks/pre-commit
     │    │
     │    ├──→ Secret Detection (grep for patterns)
     │    ├──→ ShellCheck (on *.sh files)
     │    └──→ Hadolint (on Containerfile files)
     │
     └──→ If all pass: commit proceeds
          Else: commit aborted, user must fix issues
```

### SELinux Policy Linter Flow
```
./scripts/lint-selinux-policies.sh
     │
     ├──→ For each .te file
     │    │
     │    ├──→ Static analysis (module, transitions, wildcards, etc.)
     │    └──→ Compilation check with checkmodule
     │
     └──→ Report results
```

### Compliance Test Suite Flow
```
./scripts/test-phase4-compliance.sh
     │
     ├──→ Check kernel.unprivileged_userns_clone
     ├──→ Check /etc/containers/policy.json
     ├──→ Validate devbox Containerfiles
     └──→ Check git hooks installation
```

---

*MAYOTIX OS Engineering Team*  
*Phase 4 Week 4 — September 2026*