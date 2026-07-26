# Getting help

## Start here

The [install and architecture guide](https://aethoshub.github.io/AgentAccessManager/) covers installation, configuration, day-2 operations, and how each module works. The README's [Troubleshooting](README.md#troubleshooting) section covers the handful of things that trip people up most often.

Your own install can usually tell you what is wrong:

```bash
./aimanager.sh status
```

```bash
./aimanager.sh logs
```

## Filing an issue

Open a [new issue](../../issues/new/choose). The bug report form asks for your version, platform, and how you installed. Please fill those in. Most questions that take several rounds to answer do so because the version or the install method was not clear at the start.

Include the output of `./aimanager.sh logs` where it is relevant, but **read it before pasting it**: logs from a running gateway can contain request metadata, hostnames, and user identifiers. Provider API keys and virtual keys are not logged in full, but redact anything you would not want in public.

## What this repository is

This is the **distribution** repository: releases, install scripts, and documentation. The application source is not public, so issues here are for installation, packaging, configuration, documentation, and behaviour you believe is wrong. They are not for pull requests against the implementation.

Bug reports, unclear documentation, and "the installer did something surprising" reports are all welcome, and are the most useful thing you can send.

## Security

Do not report vulnerabilities through public issues. See [SECURITY.md](SECURITY.md).

## Commercial support

The free CORE tier is self-supported through this issue tracker on a best-effort basis. For licensing, paid tiers, or a support agreement, email **hello@agentaccessmanager.com**.
