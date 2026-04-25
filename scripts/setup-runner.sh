#!/usr/bin/env bash
# Self-hosted GitHub Actions runner setup for Ubuntu (WSL2 or native)
#
# Usage:
#   chmod +x setup-runner.sh
#   ./setup-runner.sh          ← do NOT run with sudo
#
# Prerequisites:
#   - Ubuntu 22.04 or 24.04 (WSL2 works fine)
#   - At least 32 GB RAM recommended (Signal Android needs ~16 GB for Gradle)
#   - Get a runner token first:
#     GitHub repo → Settings → Actions → Runners → New self-hosted runner

set -euo pipefail

# config.sh refuses to run as root; catch it early with a clear message.
if [ "$EUID" -eq 0 ]; then
  echo "ERROR: Do not run this script with sudo / as root."
  echo "       Run as your normal user: ./setup-runner.sh"
  exit 1
fi

# ── Versions ────────────────────────────────────────────────────────────────
RUNNER_VERSION="2.334.0"           # https://github.com/actions/runner/releases
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
ANDROID_SDK_ROOT="$HOME/android-sdk"
RUNNER_DIR="$HOME/actions-runner"

# ── Install system dependencies ─────────────────────────────────────────────
echo "[1/5] Installing system packages..."
sudo apt-get update -q
sudo apt-get install -y -q \
  openjdk-17-jdk \
  curl wget unzip git \
  libicu-dev

# ── Install Android SDK ──────────────────────────────────────────────────────
echo "[2/5] Installing Android SDK..."
if [ -d "$ANDROID_SDK_ROOT/cmdline-tools/latest" ]; then
  echo "  Android SDK already present at $ANDROID_SDK_ROOT — skipping download."
else
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
  cd /tmp
  wget -q "$CMDLINE_TOOLS_URL" -O cmdline-tools.zip
  unzip -q cmdline-tools.zip -d "$ANDROID_SDK_ROOT/cmdline-tools"
  mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  rm cmdline-tools.zip
fi

export ANDROID_HOME="$ANDROID_SDK_ROOT"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

echo "  Accepting licenses..."
yes | sdkmanager --licenses > /dev/null 2>&1 || true
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"

# ── Download and extract runner ──────────────────────────────────────────────
echo "[3/5] Downloading GitHub Actions runner v${RUNNER_VERSION}..."
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"
if [ -f "$RUNNER_DIR/config.sh" ]; then
  echo "  Runner binaries already present — skipping download."
else
  curl -fsSL \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
    | tar xz
fi

# ── Configure runner ─────────────────────────────────────────────────────────
echo ""
echo "[4/5] Configuring runner..."
echo "      Go to: GitHub repo → Settings → Actions → Runners → New self-hosted runner"
echo "      Select Linux / x64, copy the token from the configure step."
echo ""

while true; do
  read -rp "  Repository URL (e.g. https://github.com/Stensel8/Signal-Android-patches): " REPO_URL
  [ -n "$REPO_URL" ] && break
  echo "  URL cannot be empty."
done

while true; do
  read -rp "  Registration token: " REG_TOKEN
  [ -n "$REG_TOKEN" ] && break
  echo "  Token cannot be empty."
done

read -rp "  Runner name [$(hostname)]: " RUNNER_NAME
RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"

"$RUNNER_DIR/config.sh" \
  --url "$REPO_URL" \
  --token "$REG_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "self-hosted,Linux,X64" \
  --unattended \
  --replace

# ── Write environment file ───────────────────────────────────────────────────
# systemd services do not source ~/.bashrc, so Android SDK paths must live here.
cat > "$RUNNER_DIR/.env" << EOF
ANDROID_HOME=$ANDROID_SDK_ROOT
ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT
PATH=$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF
echo "  Written: $RUNNER_DIR/.env"

# ── Install and start systemd service ───────────────────────────────────────
echo "[5/5] Installing systemd service..."
sudo "$RUNNER_DIR/svc.sh" install
sudo "$RUNNER_DIR/svc.sh" start

echo ""
echo "Done. Runner '${RUNNER_NAME}' is active."
echo "Check status : sudo systemctl status actions.runner.*.service"
echo "View logs    : sudo journalctl -u actions.runner.*.service -f"
echo ""
echo "To remove this runner later:"
echo "  sudo $RUNNER_DIR/svc.sh stop"
echo "  sudo $RUNNER_DIR/svc.sh uninstall"
echo "  $RUNNER_DIR/config.sh remove --token <removal-token>"
