# Security policy

Agent Access Manager sits in the request path for AI traffic and holds your vendor API keys, so we would much rather hear about a problem early than read about it later.

## Reporting a vulnerability

**Please do not open a public issue for a security report.**

Use GitHub's private vulnerability reporting: the **Report a vulnerability** button under this repository's [Security tab](../../security/advisories/new). It creates a private thread visible only to you and the maintainers.

If that is unavailable to you, email **security@agentaccessmanager.com**.

Useful things to include, as far as you have them:

- what version you are running (`./aimanager.sh status`, or the image tag)
- which component is affected: the gateway data plane, the admin API, the dashboard, the bundled Keycloak, or the installer
- what an attacker would gain, and what access they need to start with
- a reproduction, even a rough one

You do not need a polished write-up or a CVSS score. A clear description of what you found is enough.

## What to expect

We aim to acknowledge a report within three working days, and to tell you plainly whether we consider it a vulnerability and what we intend to do. If we disagree that something is exploitable, we will say why rather than go quiet.

Fixes ship as a normal release. We will credit you in the release notes if you would like, or keep you anonymous if you prefer. Just tell us which.

## Scope

In scope: the container image, the deploy kit and installers, the Helm chart, and the published install scripts, at the latest release.

Out of scope, though still worth telling us about: findings that require an already-compromised host or Docker daemon, vulnerabilities in the upstream LLM vendors themselves, and denial of service by simply sending very large volumes of traffic through your own gateway.

## Hardening notes

Two properties of a self-hosted install are worth knowing about, because they are design decisions rather than oversights:

- The installer generates a break-glass admin credential into `deploy/.env`. It is a real credential on the admin API. Treat that file as a secret, and prefer SSO for day-to-day access.
- `AIM_CATALOG_MASTER_KEY` in the same file encrypts your stored provider credentials. Anyone with that file and your database can decrypt them. It also must never change, or those credentials become unreadable.
