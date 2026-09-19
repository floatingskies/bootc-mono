#!/usr/bin/env bash
# Install Debian/Ubuntu packages with retries. Rolling releases (Debian sid
# and friends) can briefly serve a momentarily inconsistent apt index, so we
# purge stale lists, refetch, and retry --fix-missing installs before failing.
# Kept as a script (not a quoted multi-line RUN) because buildah/podman
# truncates multi-line single-quoted RUN commands at the first newline.
set -euo pipefail

# kdump-tools' kernel post-install hook builds a kdump initrd via
# initramfs-tools, which cannot determine the root device inside a build
# container ("failed to determine device for /"). kdump is useless on a bootc
# image, so pin it out; a negative priority also stops it from being pulled in
# as a Recommends of the kernel package.
mkdir -p /etc/apt/preferences.d
printf 'Package: kdump-tools\nPin: version *\nPin-Priority: -1\n' > /etc/apt/preferences.d/no-kdump

rm -f /var/lib/apt/lists/*
apt-get update -y

status=1
for i in 1 2 3; do
  # No pathname expansion: some package names (e.g. systemd-boot*) are globs
  # that apt itself understands but the shell would try to expand.
  set -f
  apt-get install -y --fix-missing "$@" && { status=0; set +f; break; } || { status=$?; set +f; sleep 15; apt-get update -y; }
done
[ "$status" -eq 0 ] || exit "$status"