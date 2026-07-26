# Agent Access Manager

An on-prem AI gateway and broker: one OpenAI-compatible endpoint in front of your LLM vendors (OpenAI, Groq, Ollama, Anthropic, Gemini, and more), with virtual keys, load-balanced routing and fallback, budgets and rate limits, content guardrails, a durable audit trail, and an optional SIEM/SOAR tier.

Documentation and install guide: **https://docs.agentaccessmanager.com/**

This repository hosts the **releases and install documentation**. The deploy kit is attached to each [release](../../releases); the container image is published to GHCR at `ghcr.io/aethoshub/agentaccessmanager`.

## Install (single host)

Requirements: Docker Engine with the Compose v2 plugin, about 4 GB of free RAM (more with the SIEM tier), and a hostname users can reach. `localhost` will not work: inside a container it resolves to the container itself.

**Linux / macOS**

```bash
curl -fsSL https://agentaccessmanager.com/get.sh | sh
```

**Windows (PowerShell)**

```powershell
irm https://agentaccessmanager.com/get.ps1 | iex
```

That is the whole install. It resolves the latest release, verifies the download's checksum, generates every secret, starts the stack, waits until the app is actually serving, and opens the dashboard. It asks nothing: the URL defaults to `http://<this-machine-hostname>:8080` and is only used once the name is confirmed to resolve. Re-run it any time to upgrade in place; your secrets and data are kept.

First boot takes a few minutes, because it migrates the database and imports the SSO realm. The installer waits for that and prints progress, so by the time it hands you a URL the dashboard is ready.

To serve at a real hostname or pin a version, pass options through the pipe:

```bash
curl -fsSL https://agentaccessmanager.com/get.sh | sh -s -- --url https://gateway.acme.com
```

```powershell
& ([scriptblock]::Create((irm https://agentaccessmanager.com/get.ps1))) -Url https://gateway.acme.com
```

Also available: `--port`, `--version vX.Y.Z`, `--image`, `--license FILE`, `--dir`, `--no-open`.

<details>
<summary>Manual install from the release kit</summary>

Download the kit from the latest [release](../../releases), then:

```bash
tar xzf aimanager-<version>-deploy.tar.gz
```

```bash
cd aimanager
```

```bash
./install.sh --url http://<your-host>:8080 --image ghcr.io/aethoshub/agentaccessmanager:<version>
```

```powershell
.\install.ps1 -Url http://<your-host>:8080 -Image ghcr.io/aethoshub/agentaccessmanager:<version>
```

Add `--yes` / `-Yes` to take every default without being prompted.
</details>

Either way the installer generates every secret into `deploy/.env` (back that file up, because `AIM_CATALOG_MASTER_KEY` must never change or stored provider credentials become undecryptable), starts the stack, and prints the dashboard URL along with the first-login credentials.

## First run

The dashboard walks you through it: create an organization, connect a provider, issue a virtual key, and send a test message without leaving the page. Then point any OpenAI-compatible client at your gateway:

```bash
curl http://<your-host>:8080/v1/chat/completions -H "Authorization: Bearer <your-virtual-key>" -H "Content-Type: application/json" -d '{"model":"<your-alias>","messages":[{"role":"user","content":"hello"}]}'
```

The same base URL works with the OpenAI SDKs, the Anthropic Messages API (`/v1/messages`), the Responses API (`/v1/responses`), and embeddings. Set `base_url` and use a virtual key as the API key.

## Licensing and tiers

The free CORE tier needs no license. Applying one unlocks the paid features at runtime, with no restart:

```bash
./aimanager.sh license <file-or-token>
```

```bash
./aimanager.sh upgrade
```

`upgrade` brings up the extra infrastructure a license unlocks, such as OpenSearch for the SIEM tier.

## Day-2 operations

```bash
./aimanager.sh restart | stop | start | logs | status
```

```bash
./aimanager.sh backup [DIR]
```

```bash
./aimanager.sh restore DIR
```

`backup` takes a consistent copy of every data volume plus the secrets. Keep those together: a backup cannot be restored without its `.env`.

To remove it:

```bash
./aimanager.sh uninstall
```

That deletes the containers and data volumes, then asks whether to delete the install directory too. Add `--purge` (`-Purge` on Windows) to delete it without being asked. The directory holds `.env`, and therefore your master key, which is why it is a separate question.

## Air-gapped install

When `images-*.tar.zst` bundles are attached to a release, load them on the target box first; the installer then runs without registry access.

```bash
zstd -d < images-base-<version>.tar.zst | docker load
```

```bash
zstd -d < images-pro-<version>.tar.zst | docker load
```

The second is only needed for the SIEM tier. You can also build a bundle on a machine that does have access, with `./aimanager.sh bundle`, and then `./aimanager.sh load` it on the target.

## Troubleshooting

**A locally hosted model is refused.** If you run Ollama, vLLM, or LM Studio on the same machine, register it as `http://host.docker.internal:11434/v1`, not `localhost`. The gateway runs in a container, so `localhost` there means the container itself and the connection is refused. On Linux, also make the model server listen beyond loopback (`OLLAMA_HOST=0.0.0.0`).

**The dashboard says it is starting.** That page is served while the app boots and refreshes itself. If it persists for more than a few minutes, check `./aimanager.sh logs`.

**Nothing resolves at the URL.** The hostname has to resolve from the machines that will use it, not only from the server. Re-run the installer with `--url` pointing at a name your users can reach, or use the host's IP address.

## Support

Open an [issue](../../issues), or see [SUPPORT.md](SUPPORT.md). For anything security-related, please follow [SECURITY.md](SECURITY.md) instead of filing a public issue.
