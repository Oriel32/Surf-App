---
name: wsl-swift-setup
description: One-time setup of the userspace Swift toolchain in WSL so SurfCore builds and tests on Windows without a Mac. Use when swift is missing, the toolchain needs reinstalling or removing, or a build is unusably slow because artifacts landed on /mnt/c.
---

# Building SurfCore on Windows (no Mac required)

Day-to-day you do not need any of this — `scripts/wsl-swift.sh` already wraps it:

```bash
./scripts/wsl-swift.sh test              # hermetic unit suite
./scripts/wsl-swift.sh run smoke hadera  # LIVE smoke test against real APIs
```

This skill is the one-time install behind that script, and how to undo it.

`SurfCore` has no Apple-framework dependencies, so it builds and tests on Linux. Verified working: **Swift 6.3.3 on WSL Ubuntu 24.04**, all 105 tests passing.

The toolchain is installed **entirely in userspace — no sudo, no system packages**:

```bash
# 1. Toolchain (~1 GB) into ~/swift
curl -fL -o swift.tar.gz \
  https://download.swift.org/swift-6.3.3-release/ubuntu2404/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE-ubuntu24.04.tar.gz
mkdir -p ~/swift && tar xzf swift.tar.gz -C ~/swift --strip-components=1

# 2. The one missing runtime lib, unpacked without root
mkdir -p ~/localdeps/debs && cd ~/localdeps/debs
apt-get download libncurses6 libtinfo6      # apt-get download needs no sudo
for d in *.deb; do dpkg -x "$d" ~/localdeps; done

# 3. Environment
export PATH="$HOME/swift/usr/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/localdeps/usr/lib/x86_64-linux-gnu:$HOME/localdeps/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"

# 4. Build with the scratch path on ext4, NOT on the /mnt/c 9p mount
swift test --package-path /mnt/c/.../SurfCore --scratch-path ~/build/surfcore
```

**WSL2's network stack drops roughly a quarter of outbound HTTPS requests here.** They hang
until the timeout rather than failing fast, on IPv4 and IPv6 alike, against every host tried.
The same requests from Windows are clean 10/10, so it is the WSL NAT layer, not the provider
and not the client. Two consequences:

- **A failing smoke run means nothing until it fails twice.** Sampling one run per spot produced
  a convincing, entirely false "this spot is broken" diagnosis. Re-run before believing it.
- It is why `RetryingTransport` exists and is on by default. Retries are correct for a phone on
  cellular regardless, but this environment is what surfaced the need.

The `--scratch-path` matters: leaving build artifacts on `/mnt/c` is the difference between an 8-second build and an unusable one. Undo everything with `rm -rf ~/swift ~/localdeps ~/build`.

`scripts/wsl-swift.sh` wraps all of the above — run it from WSL:

```bash
./scripts/wsl-swift.sh test              # hermetic unit suite
./scripts/wsl-swift.sh run smoke hadera  # LIVE smoke test against real APIs
```
