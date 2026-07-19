# Security Policy

## Reporting a Vulnerability

We take the security of Spectra seriously. If you believe you have found a security vulnerability, please report it to us as described below.

**Please do NOT report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to the project maintainers. If you do not have a specific contact, please open a regular issue with a **general description only** — without detailed exploit steps — and we will follow up.

You should receive a response within 48 hours. If you don't, please follow up to ensure we received your message.

## What to Include

To help us understand and fix the issue quickly, please include:

- Type of issue (e.g., buffer overflow, SQL injection, cross-site scripting, etc.)
- Full paths of source file(s) related to the issue
- Step-by-step instructions to reproduce
- Proof-of-concept or exploit code (if available)
- Impact of the issue (what an attacker might be able to do)

## Scope

Spectra is a local desktop application that:

- **Does not** make network requests (except for model downloads)
- **Does not** collect telemetry or usage data
- **Does not** contain remote code execution vectors by design
- Primarily operates on local files and a local SQLite database

This attack surface is intentionally limited, but vulnerabilities in image decoding, file parsing, or native FFI code should still be reported.

## Preferred Languages

We prefer all communications in English or Chinese.

## Policy

- We will acknowledge receipt of your vulnerability report within 48 hours
- We will send a more detailed response within 5 business days
- We will keep you informed of progress toward a fix
- We will publicly credit you for the discovery (unless you prefer to remain anonymous)
