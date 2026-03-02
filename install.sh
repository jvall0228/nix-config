#!/usr/bin/env bash
set -euo pipefail

# ── NixOS Install Bootstrap (run from live USB) ──────────────
# Sets up the live environment with tools + Claude Code,
# then hands off to Claude for the interactive install.
# Target: ThinkPad P15v Gen 3

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
NC='\033[0m'

REPO="https://github.com/jvall0228/nix-config.git"
WORK_DIR="/tmp/nix-config"

echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}  NixOS Install Bootstrap              ${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""

# ── 0. Must be root ──────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Run as root: sudo bash install.sh${NC}"
  exit 1
fi

# ── 1. Network check ─────────────────────────────────────────
echo -e "${YELLOW}[1/4] Checking network...${NC}"
if ! ping -c1 -W3 github.com &>/dev/null; then
  echo -e "${RED}No network. Connect first:${NC}"
  echo ""
  echo "  WiFi:"
  echo "    nmcli device wifi list"
  echo "    nmcli device wifi connect <SSID> password <PASSWORD>"
  echo ""
  echo "  Then re-run this script."
  exit 1
fi
echo -e "${GREEN}  Network OK${NC}"

# ── 2. Install tools into live env ────────────────────────────
echo ""
echo -e "${YELLOW}[2/4] Installing git + node + claude-code into live env...${NC}"
nix-env -iA nixos.git nixos.nodejs_22
npm i -g @anthropic-ai/claude-code
echo -e "${GREEN}  Tools installed${NC}"

# ── 3. Clone config ──────────────────────────────────────────
echo ""
echo -e "${YELLOW}[3/4] Cloning nix-config...${NC}"
if [[ -d "$WORK_DIR" ]]; then
  echo -e "${YELLOW}  $WORK_DIR exists, pulling latest...${NC}"
  git -C "$WORK_DIR" pull
else
  git clone "$REPO" "$WORK_DIR"
fi
echo -e "${GREEN}  Config ready at $WORK_DIR${NC}"

# ── 4. Write CLAUDE.md for the install session ────────────────
cat > "$WORK_DIR/CLAUDE.md" << 'INSTRUCTIONS'
# NixOS Installation — Live Environment

You are running in a NixOS live USB environment. Your job is to guide and execute the NixOS installation onto the ThinkPad's internal drive.

## Context

- Repo: /tmp/nix-config (the flake config)
- Host config: hosts/thinkpad/ (disko.nix defines LUKS + btrfs layout)
- Target disk: /dev/nvme0n1 (verify with `lsblk`)
- Target host: thinkpad
- Target user: javels

## Installation Steps

Run these steps one at a time, verifying each succeeds before continuing:

### Step 1 — Verify disk target
```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
```
Confirm /dev/nvme0n1 exists and is the right drive. Ask the user to confirm before proceeding.

### Step 2 — Partition with disko
```bash
nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
  --mode disko /tmp/nix-config/hosts/thinkpad/disko.nix
```
This creates: 1G ESP at /boot, LUKS-encrypted btrfs with @, @home, @nix, @swap subvolumes.
The user will be prompted for a LUKS passphrase — tell them before running.

### Step 3 — Verify mounts
```bash
lsblk -f
mount | grep /mnt
```
Expected mountpoints: /mnt, /mnt/boot, /mnt/home, /mnt/nix, /mnt/swap

### Step 4 — Generate hardware config
```bash
nixos-generate-config --no-filesystems --root /mnt --show-hardware-config \
  > /tmp/nix-config/hosts/thinkpad/hardware-configuration.nix
```
Use --no-filesystems because disko handles that.

### Step 5 — Install NixOS
```bash
nixos-install --flake /tmp/nix-config#thinkpad --no-root-passwd
```
This will take a while. If it fails, read the error carefully and troubleshoot.

### Step 6 — Set user password
```bash
nixos-enter --root /mnt -c 'passwd javels'
```

### Step 7 — Post-install guidance
Tell the user:
- Reboot, remove USB, boot into NixOS
- On first boot: disable Secure Boot in BIOS (F1 on ThinkPad)
- After first successful boot, set up lanzaboote secure boot:
  ```
  sudo sbctl create-keys
  sudo sbctl enroll-keys --microsoft
  sudo nixos-rebuild switch --flake ~/nix-config#thinkpad
  ```
- Then re-enable Secure Boot in BIOS
- Clone the config permanently: `git clone https://github.com/jvall0228/nix-config.git ~/nix-config`

## Rules
- Always verify before destructive operations — ask the user to confirm
- If a step fails, diagnose before retrying
- Show the user what you're doing at each step
INSTRUCTIONS

echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  Bootstrap complete!                  ${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo -e "  Launch Claude to begin installation:"
echo ""
echo -e "  ${CYAN}cd /tmp/nix-config && claude${NC}"
echo ""
echo -e "  Claude will walk you through each step interactively."
echo ""
