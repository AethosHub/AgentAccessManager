#!/bin/sh
#
# Agent Manager - online installer (Linux / macOS). Downloads the release deploy kit, verifies it, and runs the installer
# with sane defaults. Published to the docs site by the `release` workflow, so it is fetched over HTTPS from:
#
#   curl -fsSL https://agentaccessmanager.com/get.sh | sh
#   curl -fsSL https://agentaccessmanager.com/get.sh | sh -s -- --url https://aimanager.acme.com
#
# It asks nothing on the happy path: the public URL defaults to http://<this-hostname>:8080 and is only accepted after
# the name is confirmed to resolve from this machine (a container cannot use `localhost`, so a resolvable name is
# mandatory). Re-running it upgrades in place: deploy/.env keeps every generated secret and the master key.
#
# POSIX sh on purpose - it is piped into whatever /bin/sh is. The control script it hands off to needs bash.

set -eu

SITE="${AIM_SITE:-https://docs.agentaccessmanager.com}"
REPO="${AIM_REPO:-AethosHub/AgentAccessManager}"
# Where the release assets live. Override to install from an internal mirror instead of GitHub (the kit + SHA256SUMS
# must sit directly under it), e.g. AIM_RELEASE_BASE=https://artifacts.corp.example/aimanager/v1.2.3
RELEASE_BASE="${AIM_RELEASE_BASE:-}"
DIR="${AIM_HOME:-$HOME/.aimanager}"
PORT=8080
CHANNEL=""
VERSION=""
URL=""
IMAGE=""
LICENSE=""
OPEN=1

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32m+\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31mERROR\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
	cat <<EOF
Agent Manager - online installer

  curl -fsSL $SITE/get.sh | sh
  curl -fsSL $SITE/get.sh | sh -s -- [options]

Options
  --url URL          public URL to serve at (default http://<this-hostname>:$PORT)
  --channel NAME     install from a side channel (e.g. preview) instead of the releases
  --port N           port when deriving the default URL (default $PORT)
  --version vX.Y.Z   release to install (default: the latest stable)
  --image REF        override the container image reference
  --license FILE     apply a license as part of the install
  --dir PATH         install location (default \$HOME/.aimanager)
  --no-open          do not open a browser at the end
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--url)     URL="${2:?--url needs a value}"; shift 2;;
		--port)    PORT="${2:?--port needs a value}"; shift 2;;
		--channel) CHANNEL="${2:?--channel needs a value}"; shift 2;;
		--version) VERSION="${2:?--version needs a value}"; shift 2;;
		--image)   IMAGE="${2:?--image needs a value}"; shift 2;;
		--license) LICENSE="${2:?--license needs a value}"; shift 2;;
		--dir)     DIR="${2:?--dir needs a value}"; shift 2;;
		--no-open) OPEN=0; shift;;
		-h|--help) usage; exit 0;;
		*) usage; die "unknown option: $1";;
	esac
done

# A channel is a directory on the docs site holding its own latest.json + kit, so unreleased builds are installable
# without publishing a GitHub release. The kit comes from there too, not from the releases page.
if [ -n "$CHANNEL" ]; then
	SITE="$SITE/$CHANNEL"
	[ -n "$RELEASE_BASE" ] || RELEASE_BASE="$SITE"
fi

say ""
say "Agent Manager installer"
# Same reasoning as the PowerShell twin: an AIM_SITE inherited from the environment should never be silent.
[ -n "${AIM_SITE:-}" ] && say "  installing from AIM_SITE=$AIM_SITE (unset it to use the default)"
say ""

# ---- prerequisites -------------------------------------------------------------------------------------------------

docker_hint() {
	case "$(uname -s)" in
		Darwin) say "  Install Docker Desktop: https://docs.docker.com/desktop/install/mac-install/";;
		Linux)  say "  Install Docker Engine + the compose plugin: https://docs.docker.com/engine/install/";
		        say "  then: sudo usermod -aG docker \$USER   (and log out / back in)";;
		*)      say "  See https://docs.docker.com/get-docker/";;
	esac
}

command -v docker >/dev/null 2>&1 || { printf '\n\033[31mERROR\033[0m Docker is not installed.\n' >&2; docker_hint; exit 1; }
# A stopped daemon and a permission problem are different failures with different fixes, and collapsing them into
# "start Docker" is what sends Linux users to sudo. Installing as root then puts everything under /root: the
# install directory, and the desktop launcher, where the user's own session will never look for it.
if ! docker_err="$(docker info 2>&1 >/dev/null)"; then
	case "$docker_err" in
		*"permission denied"*|*"Permission denied"*)
			printf '\n\033[31mERROR\033[0m Your user cannot talk to the Docker daemon.\n' >&2
			say "  Add yourself to the docker group, then log out and back in (a new shell is not enough):"
			say ""
			say "    sudo usermod -aG docker \$USER"
			say ""
			say "  Do NOT re-run this with sudo. As root the install lands in /root and the launcher goes to"
			say "  /root/.local/share/applications, where your own desktop session cannot see it."
			exit 1
			;;
		*)
			die "Docker is installed but not responding - start Docker (Desktop) and re-run."
			;;
	esac
fi
docker compose version >/dev/null 2>&1 || die "the Docker Compose v2 plugin is required ('docker compose version' failed)."
command -v bash >/dev/null 2>&1 || die "bash is required (the control script uses it) - install bash and re-run."
ok "$(docker --version | sed 's/,.*//'), Compose $(docker compose version --short 2>/dev/null || echo v2)"

dl() {  # $1 = url, $2 = output path
	if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2"
	elif command -v wget >/dev/null 2>&1; then wget -qO "$2" "$1"
	else die "need curl or wget to download."; fi
}

sha256_of() {  # $1 = file
	if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
	else printf ''; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

# ---- resolve the release -------------------------------------------------------------------------------------------

if [ -z "$VERSION" ]; then
	dl "$SITE/latest.json" "$TMP/latest.json" || die "cannot reach $SITE/latest.json - pass --version vX.Y.Z, or check your network."
	VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TMP/latest.json" | head -1)"
	[ -n "$VERSION" ] || die "no version advertised at $SITE/latest.json - pass --version vX.Y.Z."
fi
ok "Release $VERSION"

# Pin the image to the release actually being installed. Without this the installer falls back to the kit's `:latest`
# default, which makes --version meaningless and outright fails on a pre-release, where no `latest` tag is published.
if [ -z "$IMAGE" ]; then
	IMAGE="ghcr.io/$(printf '%s' "$REPO" | tr '[:upper:]' '[:lower:]'):$VERSION"
fi

KIT="aimanager-$VERSION-deploy.tar.gz"
BASE="${RELEASE_BASE:-https://github.com/$REPO/releases/download/$VERSION}"
dl "$BASE/$KIT" "$TMP/$KIT" || die "could not download $BASE/$KIT - is $VERSION a published release?"

# The release always ships SHA256SUMS beside the kit; a missing one is suspicious enough to mention but not to stop for.
if dl "$BASE/SHA256SUMS" "$TMP/SHA256SUMS" 2>/dev/null; then
	expected="$(awk -v f="$KIT" '$2 == f || $2 == "*" f { print $1 }' "$TMP/SHA256SUMS" | head -1)"
	actual="$(sha256_of "$TMP/$KIT")"
	if [ -z "$expected" ]; then warn "SHA256SUMS has no entry for $KIT - skipping verification."
	elif [ -z "$actual" ]; then warn "no sha256sum/shasum on this host - skipping verification."
	elif [ "$expected" != "$actual" ]; then die "checksum mismatch for $KIT - refusing to install. Expected $expected, got $actual."
	else ok "Downloaded $KIT, checksum verified"; fi
else
	warn "no SHA256SUMS published for $VERSION - skipping verification."
fi

# ---- unpack --------------------------------------------------------------------------------------------------------

# The kit archives everything under a top-level `aimanager/`, so strip it and land the contents directly in $DIR.
# An existing install is overwritten except deploy/.env, which the kit does not contain - so secrets survive an upgrade.
mkdir -p "$DIR"
tar xzf "$TMP/$KIT" -C "$DIR" --strip-components=1 || die "could not unpack $KIT into $DIR."
[ -f "$DIR/aimanager.sh" ] || die "$DIR/aimanager.sh missing after unpack - the kit layout is not what was expected."
chmod +x "$DIR"/*.sh 2>/dev/null || true
ok "Installed to $DIR"

# ---- choose the URL ------------------------------------------------------------------------------------------------

# $1 = hostname. Three-state on purpose: 0 = resolves, 1 = definitively does not, 2 = could not tell. Only a
# definitive "no" is worth stopping an install for - guessing wrong and refusing to install is the worse failure.
resolve_state() {
	if command -v getent >/dev/null 2>&1; then
		getent hosts "$1" >/dev/null 2>&1 && return 0
		return 1
	fi
	if command -v dscacheutil >/dev/null 2>&1; then   # macOS has no getent
		dscacheutil -q host -a name "$1" 2>/dev/null | grep -q 'ip_address' && return 0
		return 1
	fi
	# Being on PATH is not proof it runs: Windows ships a python3.exe App Execution Alias that only advertises the
	# Microsoft Store. Probe it before trusting its answer, or a working host gets reported as unresolvable.
	if command -v python3 >/dev/null 2>&1 && python3 -c '' >/dev/null 2>&1; then
		python3 -c 'import socket,sys; socket.getaddrinfo(sys.argv[1], None)' "$1" >/dev/null 2>&1 && return 0
		return 1
	fi
	if command -v ping >/dev/null 2>&1; then
		# Flags differ per platform: BSD/macOS -t seconds, Linux -w seconds, Windows ping.exe -n count / -w millis
		# (and it rejects -c outright). Getting this wrong is what made a resolvable host look unresolvable.
		case "$(uname -s)" in
			Darwin)      ping -c 1 -t 1 "$1" >/dev/null 2>&1 && return 0;;
			Linux)       ping -c 1 -w 1 "$1" >/dev/null 2>&1 && return 0;;
			MINGW*|MSYS*|CYGWIN*) ping -n 1 -w 1000 "$1" >/dev/null 2>&1 && return 0;;
			*)           ping -c 1 "$1" >/dev/null 2>&1 && return 0;;
		esac
		return 2   # a firewall dropping ICMP is not proof that DNS failed
	fi
	return 2
}

port_busy() {  # $1 = port. Only used to pick a friendlier default, so "cannot tell" means "assume free".
	if command -v ss >/dev/null 2>&1; then ss -ltn 2>/dev/null | grep -q "[:.]$1[[:space:]]" && return 0; return 1; fi
	if command -v netstat >/dev/null 2>&1; then netstat -an 2>/dev/null | grep -i 'listen' | grep -q "[:.]$1[[:space:]]" && return 0; return 1; fi
	return 1
}

if [ -z "$URL" ]; then
	host="$(hostname 2>/dev/null || echo localhost)"
	case "$host" in
		localhost|localhost.*|"")
			die "this machine's hostname is '$host', which a container resolves to itself.
  Give it a name that resolves here, e.g.:  ... | sh -s -- --url http://myhost:$PORT";;
	esac
	resolve_state "$host" || case $? in
		1) die "'$host' is this machine's hostname but does not resolve from here, so a browser could not reach it.
  Fix it with either:
    1. add it to your hosts file:   echo '127.0.0.1 $host' | sudo tee -a /etc/hosts
    2. or pass a name that resolves: ... | sh -s -- --url http://<name-or-dns>:$PORT
  (Note: 'localhost' cannot be used - a container resolves it to itself, so the app could not reach its bundled IdP.)";;
		*) warn "could not verify that '$host' resolves here - continuing anyway.";
		   warn "If the dashboard does not load, add '127.0.0.1 $host' to /etc/hosts or re-run with --url.";;
	esac
	# Only auto-shift the port when the caller did not pin one, so an explicit --port is never silently ignored.
	if port_busy "$PORT"; then
		free=""
		for candidate in 8081 8082 8083 8090 9080; do
			port_busy "$candidate" || { free="$candidate"; break; }
		done
		[ -n "$free" ] || die "port $PORT is in use and no fallback port was free - pass --port N."
		warn "Port $PORT is in use - using $free instead"
		PORT="$free"
	fi
	URL="http://$host:$PORT"
	ok "Hostname '$host' resolves - serving at $URL"
else
	ok "Serving at $URL (as requested)"
fi

# ---- hand off to the control script --------------------------------------------------------------------------------

say ""
set -- install --yes --url "$URL"
[ -n "$IMAGE" ] && set -- "$@" --image "$IMAGE"
[ -n "$LICENSE" ] && set -- "$@" --license "$LICENSE"
# stdin is the pipe this script came down, so close it: the control script must never try to read a prompt from it.
"$DIR/aimanager.sh" "$@" </dev/null

# ---- open a browser ------------------------------------------------------------------------------------------------

if [ "$OPEN" = 1 ]; then
	target="$URL/dashboard"
	case "$(uname -s)" in
		Darwin) command -v open >/dev/null 2>&1 && { say "Opening $target ..."; open "$target" >/dev/null 2>&1 || true; };;
		*)
			# A headless server has no browser to open; the printed URL is the whole answer there.
			if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && command -v xdg-open >/dev/null 2>&1; then
				say "Opening $target ..."
				xdg-open "$target" >/dev/null 2>&1 || true
			fi
			;;
	esac
fi
