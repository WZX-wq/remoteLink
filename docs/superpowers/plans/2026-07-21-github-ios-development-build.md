# GitHub iOS Development Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a manually dispatched GitHub Actions workflow that builds a development-signed IPA for the registered iPhone without committing signing material.

**Architecture:** Keep Apple credentials exclusively in GitHub Actions secrets. Align the Xcode project team with the supplied development profiles, import the certificate and profiles into an ephemeral macOS keychain at runtime, export with `method=development`, and upload the resulting IPA as a short-lived artifact.

**Tech Stack:** GitHub Actions, macOS runner, Flutter 3.44.5, Rust 1.75, Xcode code signing, PowerShell static readiness checks.

---

### Task 1: Align the Xcode project with the supplied development team

**Files:**
- Modify: `flutter/ios/Runner.xcodeproj/project.pbxproj`
- Modify: `scripts/test-kq-ios-build-readiness.ps1`

- [ ] Add a failing readiness assertion requiring every Runner and broadcast target configuration to use team `G4C3ADW2F4`.
- [ ] Run the readiness script and verify it fails because the project still contains the old team ID.
- [ ] Replace the six target-level team settings with `G4C3ADW2F4`.
- [ ] Rerun the readiness script and verify the existing checks plus the team assertion pass.

### Task 2: Add a secret-only development signing workflow

**Files:**
- Create: `.github/workflows/ios-development-build.yml`
- Modify: `.gitignore`
- Modify: `scripts/test-kq-ios-build-readiness.ps1`

- [ ] Add a failing readiness assertion requiring a manually dispatched workflow, GitHub Secrets inputs, a temporary keychain, development export options, and an IPA artifact upload.
- [ ] Run the readiness script and verify it fails because the workflow does not exist.
- [ ] Add the workflow without certificate files, profile files, passwords, or plaintext credential values.
- [ ] Allow `.github/workflows/*.yml` to be tracked while retaining the existing ignore rule for any other local workflow artifacts.
- [ ] Rerun the readiness script and YAML parse validation.

### Task 3: Publish and execute the workflow

**Files:**
- Commit only the Xcode team setting, GitHub workflow, static check, and ignore-rule changes.

- [ ] Configure the four signing secrets through GitHub authentication without using the supplied account password in Git, scripts, or workflow files.
- [ ] Push the focused commit to the existing `github` remote.
- [ ] Manually dispatch the workflow and verify the uploaded IPA artifact and Xcode signing identities from GitHub Actions logs.
