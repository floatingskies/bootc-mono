# Bootcrew

This is a monorepo for all the Bootcrew images! These are multiple different container images made for usage with [`bootc`](https://github.com/bootc-dev/bootc), they can be used as a base to build upon and make your own full images for your usecase, similar to the work from the [Fedora Bootc Base Images](https://docs.fedoraproject.org/en-US/bootc/base-images/) and [Universal Blue](http://universal-blue.org/).

## Building and Running

In order to get a running system you can run `just build (subdirectory)`, then generate a disk image with `just disk-image (subdirectory)` for any of the images to be used. 

## Daily-driver tooling: Homebrew + CLI addons

Every image ships [Homebrew on Linux](https://docs.brew.sh/Homebrew-on-Linux) at the
standard prefix `/home/linuxbrew/.linuxbrew`, plus a curated set of CLI tools
installed through it:

`eza`, `bat`, `ripgrep`, `fd`, `fzf`, `zoxide`, `btop`, `tmux`, `fastfetch`,
`starship`, `gh`, `git-lfs`, `jq`

Homebrew persists across updates: it physically lives under `/var/home/linuxbrew`
(the `/home -> /var/home` sysroot symlink) and bootc seeds `/var` onto the mutable
var partition on your first deployment. After that, updates and rollbacks never
touch it — `brew` updates itself and your tools independently of the OS.

Brew is added to your `PATH` via `/etc/profile.d/homebrew.sh`, so log in (or
restart your shell) and `brew --version` should work. For a **single-user daily
driver**, claim the tree after first login so `brew install` works without sudo:

```sh
sudo chown -R "$(id -u):$(id -g)" /home/linuxbrew/.linuxbrew
```

Multi-user hosts can instead run brew as its dedicated user via
`sudo -iu linuxbrew brew install <pkg>`. The `linuxbrew` user/group and home
directory are defined through `sysusers.d`/`tmpfiles.d`, so they stay
reproducible across upgrades.

The Homebrew bootstrap and the addon list live in `shared/linuxbrew.sh`; the
per-distro build tools it needs (`build-essential` / `base-devel` / the
equivalent zypper set) are added in each `Containerfile`.

## Image signing

Published images are signed with cosign using a key stored in the
`SIGNING_SECRET` repository secret. The `shared/signing-key.sh` helper in the
CI normalizes the secret before signing, so either the raw PEM from
`cosign generate-key-pair` or `base64 -w0 cosign.key` works. If the key is
password-protected, set the optional `SIGNING_PASSWORD` secret.

### Objective

None of these should need to exist, ideally all of these projects would directly publish `(project-name)-bootc` images, or at least provide a `bootc` package or bundle for it. We aim to make our images as small and basic as possible to minimize maintenance burden and make it easier to upstream any effors from them.
