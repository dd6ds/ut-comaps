#!/usr/bin/env bash
# Build and install ut-comaps (CoMaps for Ubuntu Touch).
#
# CoMaps is a big C++ build. Locally it runs arm64-emulated (qemu) and takes
# hours; GitHub Actions builds it natively in ~15 minutes (warm cache). So:
#
#   ./build.sh ci                 start the GitHub build, wait, download the click to build/
#   ./build.sh release 0.1.0      tag v0.1.0: GitHub builds a release with exactly this
#                                 version (for the OpenStore), the click lands in build/
#   ./build.sh download           download the click of the latest GitHub release to build/
#   ./build.sh phone [file.click] install the newest click in build/ (or the given one) on
#                                 the phone over adb (USB) and start it
#   ./build.sh                    build locally with Clickable (Docker + qemu, slow)
#   ./build.sh local-phone        build locally, then install as above
#   ./build.sh <clickable args>   any other Clickable command, e.g. "script source", "clean"
#
# Only Docker is needed on the computer: Clickable itself runs in a container
# (the same "clickable-runner" image as the other projects) and starts the
# arm64 build container ut-comaps:noble-arm64 through the computer's Docker.

set -euo pipefail

CLICKABLE_VERSION="8.10.0"
IMAGE="clickable-runner:${CLICKABLE_VERSION}"
BUILD_IMAGE="ut-comaps:noble-arm64"
REPO="dd6ds/ut-comaps"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$PROJECT_DIR/build"

die() {
    echo "build.sh: $*" >&2
    exit 1
}

check_docker() {
    command -v docker >/dev/null || die "Docker is not installed."
    docker info >/dev/null 2>&1 \
        || die "Docker is not running or you may not use it (sudo systemctl start docker;" \
               "sudo usermod -aG docker $USER, then log in again)."
}

# --- Local build ---------------------------------------------------------------

# Clickable, adb and ssh in one image, built once and reused by every project.
build_runner_image() {
    docker image inspect "$IMAGE" >/dev/null 2>&1 && return
    echo "build.sh: building $IMAGE (once)"
    docker build -t "$IMAGE" --build-arg CLICKABLE_VERSION="$CLICKABLE_VERSION" - <<'DOCKERFILE'
FROM docker:cli AS docker
FROM python:3.12-slim
ARG CLICKABLE_VERSION
RUN apt-get update \
    && apt-get install -y --no-install-recommends adb openssh-client git \
    && rm -rf /var/lib/apt/lists/*
COPY --from=docker /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins
RUN pip install --no-cache-dir "clickable-ut==${CLICKABLE_VERSION}"
DOCKERFILE
}

# The noble/arm64 toolchain image clickable.json asks for. On amd64 it needs qemu.
build_toolchain_image() {
    docker image inspect "$BUILD_IMAGE" >/dev/null 2>&1 && return
    if [[ "$(uname -m)" != "aarch64" ]]; then
        docker run --rm --platform linux/arm64 ubuntu:24.04 uname -m >/dev/null 2>&1 \
            || die "arm64 containers do not run here. Install qemu:" \
                   "sudo apt install qemu-user-static binfmt-support"
    fi
    echo "build.sh: building $BUILD_IMAGE (once, takes a while)"
    docker build --platform linux/arm64 -t "$BUILD_IMAGE" -f "$PROJECT_DIR/Dockerfile.noble-arm64" "$PROJECT_DIR"
}

# Clickable mounts host paths into its build containers under the same path,
# so the project must have the same path in here as on the computer. The
# computer's user, home, ~/.ssh and ~/.android (the adb key the phone already
# trusts) are passed in, so files belong to you and ssh/adb work as outside.
run_clickable() {
    local socket="/var/run/docker.sock"
    [[ "${DOCKER_HOST:-}" == unix://* ]] && socket="${DOCKER_HOST#unix://}"
    [[ -S "$socket" ]] || die "Docker socket $socket not found."

    mkdir -p "$HOME/.clickable/docker-config" "$HOME/.android"
    local args=(
        --rm -i
        --network host
        --user "$(id -u):$(id -g)"
        --group-add "$(stat -c %g "$socket")"
        -v "$socket:/var/run/docker.sock"
        -v /etc/passwd:/etc/passwd:ro
        -v /etc/group:/etc/group:ro
        -v "$PROJECT_DIR:$PROJECT_DIR"
        -v "$HOME/.clickable:$HOME/.clickable"
        -v "$HOME/.android:$HOME/.android"
        -w "$PROJECT_DIR"
        -e HOME="$HOME"
        -e USER="$USER"
        -e DOCKER_CONFIG="$HOME/.clickable/docker-config"
        -e CLICKABLE_SKIP_DOCKER_CHECKS=1
    )
    [[ -d "$HOME/.ssh" ]] && args+=(-v "$HOME/.ssh:$HOME/.ssh")
    [[ -d /dev/bus/usb ]] && args+=(--privileged -v /dev/bus/usb:/dev/bus/usb)
    [[ -t 0 && -t 1 ]] && args+=(-t)

    docker run "${args[@]}" "$IMAGE" clickable "$@"
}

local_build() {
    check_docker
    build_runner_image
    build_toolchain_image
    [[ -d "$PROJECT_DIR/source/comaps" ]] || run_clickable script source
    run_clickable build
    # clickable leaves the click in build/<arch>/app/
    local click
    click="$(ls -t "$OUT_DIR"/*/app/*.click 2>/dev/null | head -n 1 || true)"
    [[ -n "$click" ]] && cp "$click" "$OUT_DIR/" && echo "build.sh: $OUT_DIR/$(basename "$click")"
}

# --- GitHub build ---------------------------------------------------------------

github_token() {
    [[ -n "${GH_TOKEN:-}" ]] && { echo "$GH_TOKEN"; return; }
    printf 'protocol=https\nhost=github.com\n\n' | git -C "$PROJECT_DIR" credential fill 2>/dev/null \
        | sed -n 's/^password=//p'
}

api() {
    curl -fsSL -H "Accept: application/vnd.github+json" "$@"
}

latest_release_click_url() {
    api "https://api.github.com/repos/$REPO/releases?per_page=1" \
        | python3 -c 'import json,sys
r = json.load(sys.stdin)[0]
print(next(a["browser_download_url"] for a in r["assets"] if a["name"].endswith(".click")))'
}

download() {
    mkdir -p "$OUT_DIR"
    local url
    url="$(latest_release_click_url)" || die "no release found for $REPO"
    echo "build.sh: downloading $(basename "$url")"
    curl -fL --progress-bar -o "$OUT_DIR/$(basename "$url")" "$url"
    echo "build.sh: $OUT_DIR/$(basename "$url")"
}

ci() {
    local token
    token="$(github_token)"
    [[ -n "$token" ]] || die "no GitHub token (set GH_TOKEN or store git credentials for github.com)"
    git -C "$PROJECT_DIR" fetch -q origin
    if [[ "$(git -C "$PROJECT_DIR" rev-parse HEAD)" != "$(git -C "$PROJECT_DIR" rev-parse origin/main)" ]]; then
        echo "build.sh: note: local HEAD differs from origin/main - GitHub builds origin/main (git push first?)"
    fi
    local before
    before="$(latest_run_id)"
    curl -fsS -X POST -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$REPO/actions/workflows/build.yml/dispatches" \
        -d '{"ref":"main","inputs":{"release":true}}' >/dev/null
    wait_for_run "$before"
    download_artifact
}

latest_run_id() {
    api "https://api.github.com/repos/$REPO/actions/runs?per_page=1" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["workflow_runs"][0]["id"])'
}

# Waits for the first workflow run newer than run id $1; sets RUN_ID.
RUN_ID=""
wait_for_run() {
    local before="$1" id="" status="" conclusion=""
    echo "build.sh: GitHub build started, waiting (usually 10-20 minutes) ..."
    while :; do
        sleep 30
        read -r id status conclusion < <(api "https://api.github.com/repos/$REPO/actions/runs?per_page=1" \
            | python3 -c 'import json,sys
r = json.load(sys.stdin)["workflow_runs"][0]
print(r["id"], r["status"], r["conclusion"])')
        [[ "$id" == "$before" ]] && continue
        echo "  $(date +%H:%M:%S) $status"
        [[ "$status" == "completed" ]] && break
    done
    RUN_ID="$id"
    [[ "$conclusion" == "success" ]] \
        || echo "build.sh: note: the run ended with '$conclusion' - using its click artifact if there is one" \
                "(https://github.com/$REPO/actions/runs/$id)"
}

# Downloads the click artifact of run $RUN_ID into build/; sets CLICK.
CLICK=""
download_artifact() {
    local token url name
    token="$(github_token)"
    [[ -n "$token" ]] || die "no GitHub token"
    read -r url name < <(api -H "Authorization: Bearer $token" \
        "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID/artifacts" \
        | python3 -c 'import json,sys
a = [x for x in json.load(sys.stdin)["artifacts"] if not x["expired"]]
print(a[0]["archive_download_url"], a[0]["name"]) if a else print("")')
    [[ -n "${url:-}" ]] || die "the build produced no click: https://github.com/$REPO/actions/runs/$RUN_ID"
    mkdir -p "$OUT_DIR"
    local zip="$OUT_DIR/$name.zip"
    echo "build.sh: downloading $name"
    curl -fL --progress-bar -H "Authorization: Bearer $token" -o "$zip" "$url"
    python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$zip" "$OUT_DIR"
    rm -f "$zip"
    CLICK="$(ls -t "$OUT_DIR"/*.click | head -n 1)"
    echo "build.sh: $CLICK"
}

# Creates the GitHub release for tag $1 with $CLICK if the workflow could not.
ensure_release() {
    local tag="$1" token
    token="$(github_token)"
    api "https://api.github.com/repos/$REPO/releases/tags/$tag" >/dev/null 2>&1 && return
    echo "build.sh: creating the GitHub release $tag"
    local upload
    upload="$(curl -fsS -X POST -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$REPO/releases" \
        -d "{\"tag_name\":\"$tag\",\"name\":\"ut-comaps $tag\",\"body\":\"CoMaps für Ubuntu Touch (arm64, Noble/24.04 und neuer). Kartendaten © OpenStreetMap-Mitwirkende (ODbL), CoMaps Apache-2.0.\"}" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["upload_url"].split("{")[0])')" \
        || { echo "build.sh: could not create the release (the click is in build/ anyway)" >&2; return; }
    curl -fsS -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/octet-stream" \
        --data-binary @"$CLICK" "$upload?name=$(basename "$CLICK")" >/dev/null \
        && echo "build.sh: https://github.com/$REPO/releases/tag/$tag"
}

# Release with a clean version (OpenStore): tag v<version> on origin/main.
release() {
    local version="${1:-}"
    [[ "$version" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || die "usage: ./build.sh release <version>, e.g. 0.1.0"
    local tag="v$version"
    git -C "$PROJECT_DIR" fetch -q --tags origin
    git -C "$PROJECT_DIR" rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "tag $tag exists already"
    [[ -z "$(git -C "$PROJECT_DIR" status --porcelain --untracked-files=no)" ]] \
        || die "uncommitted changes - commit (and push) first"
    [[ "$(git -C "$PROJECT_DIR" rev-parse HEAD)" == "$(git -C "$PROJECT_DIR" rev-parse origin/main)" ]] \
        || die "HEAD is not origin/main - push first"
    local before
    before="$(latest_run_id)"
    git -C "$PROJECT_DIR" tag -a "$tag" -m "ut-comaps $version"
    git -C "$PROJECT_DIR" push -q origin "$tag"
    wait_for_run "$before"
    download_artifact
    [[ "$(basename "$CLICK")" == "ut-comaps_${version}_arm64.click" ]] \
        || echo "build.sh: warning: expected ut-comaps_${version}_arm64.click" >&2
    ensure_release "$tag"
    echo "build.sh: for the OpenStore upload: $CLICK"
}

# --- Phone ------------------------------------------------------------------------

phone() {
    command -v adb >/dev/null || die "adb is not installed (sudo apt install adb)."
    local click="${1:-}"
    [[ -n "$click" ]] || click="$(ls -t "$OUT_DIR"/*.click 2>/dev/null | head -n 1 || true)"
    [[ -f "$click" ]] || die "no click found - run './build.sh ci' or './build.sh download' first"
    adb get-state >/dev/null 2>&1 || die "no phone connected (adb devices)"

    local name
    name="$(basename "$click")"
    # Version from the click itself (name: ut-comaps_<version>_arm64.click).
    local version="${name#ut-comaps_}"
    version="${version%_*.click}"

    echo "build.sh: installing $name"
    adb push "$click" "/home/phablet/Downloads/$name" >/dev/null
    # Note: "adb shell" on UT does not pass the exit code back, so decide by output.
    # Newer images (UT 26.04) have no pkcon; then click install with sudo,
    # which asks for the phone's password here in the terminal.
    if [[ -n "$(adb shell 'command -v pkcon' | tr -d '\r')" ]]; then
        adb shell "pkcon install-local --allow-untrusted -y '/home/phablet/Downloads/$name'"
    else
        # sudo needs the phone's password. "adb shell -t" would let sudo ask,
        # but UT's adbd then never closes the session, so ask here and pass it
        # base64-encoded (any characters are safe). UT_PW skips the question.
        local pw="${UT_PW:-}"
        if [[ -z "$pw" ]]; then
            read -r -s -p "Password of the phone (for sudo click install): " pw
            echo
        fi
        local b64
        b64="$(printf '%s\n' "$pw" | base64 -w0)"
        adb shell "echo $b64 | base64 -d | sudo -S -p '' click install --user=phablet --allow-unauthenticated '/home/phablet/Downloads/$name' 2>&1 | grep -v 'Signature check failed'" || true
    fi
    adb shell "rm -f '/home/phablet/Downloads/$name'"

    local installed
    installed="$(adb shell "click list" | tr -d '\r' | awk '$1 == "ut-comaps" {print $2}')"
    [[ "$installed" == "$version" ]] \
        || die "installation failed (installed version: ${installed:-none})"

    # Start it in the phone's session (app id = <package>_<app>_<version>).
    adb shell "export XDG_RUNTIME_DIR=/run/user/\$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus;
               lomiri-app-launch ut-comaps_ut-comaps_$version" >/dev/null 2>&1 || true
    echo "build.sh: installed and started ut-comaps $version"
}

main() {
    [[ -n "${USER:-}" ]] || USER="$(id -un)"
    case "${1:-}" in
        "") local_build ;;
        ci) ci ;;
        release) shift; release "${1:-}" ;;
        download) download ;;
        phone) shift; phone "${1:-}" ;;
        local-phone) local_build; phone ;;
        -h|--help|help) sed -n '2,17p' "$0" ;;
        *) check_docker; build_runner_image; run_clickable "$@" ;;
    esac
}

main "$@"
