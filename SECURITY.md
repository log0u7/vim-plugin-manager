# Security Policy

## Reporting a vulnerability

Do not open a public issue for security problems.

Use GitHub private vulnerability reporting: repository page -> Security ->
Report a vulnerability. Include reproduction steps, affected versions, and
impact. You will get an acknowledgment within 72 hours.

## Scope

- Report anything that lets untrusted input execute code, escape the
  intended data path, or read files beyond intended scope.
- Treat untrusted-content handling (prompt injection, parser confusion,
  path traversal) as in scope.

## Hardening notes

- Secrets are never committed: scanning runs in pre-commit and CI.
- Validate inputs at trust boundaries; deny by default.