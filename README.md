# AI Manager

An on-prem AI gateway and broker: one OpenAI-compatible endpoint in front of your LLM vendors (OpenAI, Groq, Ollama, Anthropic, Gemini, and more), with virtual keys, load-balanced routing and fallback, budgets and rate limits, content guardrails, a durable audit trail, and an optional SIEM/SOAR tier.

Documentation and install guide: **https://aethoshub.github.io/AgentAccessManager/**

This repository hosts the **releases and install documentation**. The deploy kit is attached to each [release](../../releases); the container image is published to GHCR at `ghcr.io/aethoshub/agentaccessmanager`.

## Install (single host)

Requirements: Docker Engine with the Compose v2 plugin, about 4 GB of free RAM (more with the SIEM tier), and a hostname users can reach. `localhost` will not work: inside a container it resolves to the container itself.

Download the kit from the latest [release](../../releases), then:

```bash
tar xzf aimanager-<version>-deploy.tar.gz && cd aimanager
./install.sh --url http://<your-host>:8080 --image ghcr.io/aethoshub/agentaccessmanager:<version>
```

Windows (PowerShell):

```powershell
.\install.ps1 -Url http://<your-host>:8080 -Image ghcr.io/aethoshub/agentaccessmanager:<version>
```

The installer generates every secret into `deploy/.env` (back that file up; `AIM_CATALOG_MASTER_KEY` must never change or stored provider credentials become undecryptable), starts the stack, and prints the dashboard URL plus the first-login credentials. Point an OpenAI client at `http://<your-host>:8080/v1` with a virtual key issued from the dashboard.

## License and tiers

The free CORE tier needs no license. Applying a license unlocks the paid features at runtime, no restart needed:

```bash
./aimanager.sh license <file-or-token>   # apply or replace the license
./aimanager.sh upgrade                   # bring up the infra the license unlocks (OpenSearch for SIEM)
```

## Day-2 operations

```bash
./aimanager.sh restart | stop | start | logs | status | uninstall
```

`uninstall` removes the containers and data volumes but keeps `deploy/.env`; delete that file too for a full secret reset.

## Air-gapped install

When `images-*.tar.zst` bundles are attached to the release, load them on the target box first; the installer then runs without registry access (its image pull failing offline is tolerated):

```bash
zstd -d < images-base-<version>.tar.zst | docker load
zstd -d < images-pro-<version>.tar.zst | docker load   # SIEM tier only
```

## Support

Open an [issue](../../issues).
