# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| none released yet | the `main` branch receives fixes |

No version of glyphsift has been released. Until the first tag, security fixes land on `main`.

## Reporting a vulnerability

Email jtushar53@gmail.com with a description, a reproducer and the commit you tested. You will get
an acknowledgement within 7 days.

We follow a 90-day coordinated disclosure window: we aim to ship a fix and publish an advisory
within 90 days of the report, and ask reporters to hold details until then (or until the fix is
public, whichever is earlier). Credit is given unless you ask otherwise.

## Scope

In scope: the Rust core, the CLI, the Python wheel, the WASM build and the build scripts in this
repository. Panics or unbounded memory use on crafted input are security bugs for a library that
scores untrusted text.

## Statements

- Test key material: any RFC 8032 Ed25519 test-vector key material appearing in Airplane Mode Labs
  repositories is public test data from the RFC and must never be trusted outside tests. glyphsift
  itself carries no keys.
- No telemetry: glyphsift collects no telemetry and makes no network requests, so there is nothing
  to opt out of.
- No secrets: this repository contains no credentials. Synthetic test inputs only.
