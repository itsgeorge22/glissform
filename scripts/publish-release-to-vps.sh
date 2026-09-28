#!/usr/bin/env bash
# Publish an immutable DMG before atomically replacing its signed update feed.
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "Usage: $0 VERSION DMG CHECKSUM APPCAST SSH_KEY" >&2
  exit 2
fi

version="$1"
dmg="$2"
checksum="$3"
appcast="$4"
key="$5"
host='glissform-deploy@159.194.226.154'
known_hosts="$(cd "$(dirname "$0")/.." && pwd)/config/release-known-hosts"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ]] || { echo 'Invalid release version.' >&2; exit 1; }
[[ "$(basename "$dmg")" == "Glissform-$version.dmg" ]] || { echo 'Unexpected DMG name.' >&2; exit 1; }
[[ "$(basename "$checksum")" == "Glissform-$version.dmg.sha256" ]] || { echo 'Unexpected checksum name.' >&2; exit 1; }
[[ -s "$dmg" && -s "$checksum" && -s "$appcast" && -s "$key" && -s "$known_hosts" ]] || { echo 'Missing release input.' >&2; exit 1; }

ssh_opts=(-i "$key" -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$known_hosts")
stage="$(ssh "${ssh_opts[@]}" "$host" mktemp -d /home/glissform-deploy/tmp.XXXXXX)"
[[ "$stage" == /home/glissform-deploy/tmp.* ]] || { echo 'Unexpected staging path.' >&2; exit 1; }
cleanup() { ssh "${ssh_opts[@]}" "$host" "rm -r -- '$stage'"; }
trap cleanup EXIT

scp "${ssh_opts[@]}" "$dmg" "$checksum" "$appcast" "$host:$stage/"
ssh "${ssh_opts[@]}" "$host" "bash -s -- '$version' '$stage'" <<'REMOTE'
set -euo pipefail
version="$1"
stage="$2"
dest='/var/www/glissform.app/downloads'
name="Glissform-$version.dmg"
cd "$stage"
sha256sum -c "$name.sha256"
for file in "$name" "$name.sha256"; do
  if [[ -e "$dest/$file" ]]; then
    cmp "$file" "$dest/$file" || { echo "Existing public $file differs." >&2; exit 1; }
  else
    chmod 644 "$file"
    mv "$file" "$dest/$file"
  fi
done
cd "$dest"
sha256sum -c "$name.sha256"
REMOTE

base="https://glissform.app/downloads/Glissform-$version.dmg"
remote_hash="$(curl --fail --location --silent --show-error "$base.sha256" | awk '{print $1}')"
local_hash="$(shasum -a 256 "$dmg" | awk '{print $1}')"
[[ "$remote_hash" == "$local_hash" ]] || { echo 'Published checksum differs.' >&2; exit 1; }
[[ "$(curl --fail --location --silent --show-error "$base" | shasum -a 256 | awk '{print $1}')" == "$local_hash" ]] || { echo 'Published DMG differs.' >&2; exit 1; }

# The feed is last: clients must never see an item before its DMG is available.
ssh "${ssh_opts[@]}" "$host" "bash -s -- '$stage'" <<'REMOTE'
set -euo pipefail
stage="$1"
chmod 644 "$stage/appcast.xml"
mv -f "$stage/appcast.xml" /var/www/glissform.app/updates/appcast.xml
REMOTE

public_feed="$(mktemp)"
trap 'rm -f "$public_feed"; cleanup' EXIT
for attempt in 1 2 3 4 5; do
  if curl --fail --location --silent --show-error 'https://glissform.app/updates/appcast.xml' -o "$public_feed" \
      && cmp -s "$appcast" "$public_feed"; then
    echo "Published Glissform $version and its signed update feed."
    exit 0
  fi
  sleep 2
done
echo 'The public update feed does not match the signed release.' >&2
exit 1
