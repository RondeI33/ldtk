#!/usr/bin/env bash
# Notify a published LDTK-Smartive release. This script deliberately does not
# build, edit, or republish release artifacts.
set -euo pipefail

tag="${1:-}"
if [[ ! "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
  echo "::error::Expected a stable Smartive tag such as v1.0.32" >&2
  exit 2
fi
version="${BASH_REMATCH[1]}"

if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
  echo "::error::Missing repository Actions secret SLACK_WEBHOOK_URL; no announcement was sent." >&2
  exit 2
fi
if [[ -z "${GH_TOKEN:-}" || -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "::error::GH_TOKEN and GITHUB_REPOSITORY are required." >&2
  exit 2
fi

release_json="$(mktemp)"
payload="$(mktemp)"
trap 'rm -f "$release_json" "$payload"' EXIT

gh release view "$tag" --repo "$GITHUB_REPOSITORY" \
  --json name,url,body,isDraft,isPrerelease,assets > "$release_json"

if ! jq -e '.isDraft == false and .isPrerelease == false and (.url | length > 0)' "$release_json" >/dev/null; then
  echo "::error::Release $tag must exist and be a published stable release before notifying Slack." >&2
  exit 1
fi

# Do not announce a release that has only a subset of platform downloads.
for filename in \
  "LDTK-Smartive-${version}-win-x64.exe" \
  "LDTK-Smartive-${version}-mac-universal.dmg" \
  "LDTK-Smartive-${version}-linux-x86_64.AppImage" \
  "latest.yml"; do
  if ! jq -e --arg filename "$filename" 'any(.assets[]; .name == $filename)' "$release_json" >/dev/null; then
    echo "::error::Release $tag is missing artifact $filename; Slack notification blocked." >&2
    exit 1
  fi
done

release_url="$(jq -r '.url' "$release_json")"
release_body="$(jq -r '.body // ""' "$release_json")"
patch_notes="$(printf '%s\n' "$release_body" | awk '
  BEGIN { count=0 }
  /^LDTK-Smartive / { next }
  /^Compatibility:/ { next }
  /^#+[[:space:]]/ { next }
  /^[[:space:]]*$/ { next }
  {
    line=$0
    gsub(/\*\*/, "", line)
    sub(/^- /, "", line)
    if (line != "") {
      print "•  " line
      count++
    }
    if (count == 3) exit
  }
')"
if [[ -z "$patch_notes" ]]; then
  patch_notes="•  Pełne patch notes znajdziesz na stronie release."
fi

jq -n --arg version "$tag" --arg url "$release_url" --arg patch_notes "$patch_notes" '{
  text: ("Nowa wersja LDTK-Smartive " + $version),
  blocks: [
    {type:"section", text:{type:"mrkdwn", text:("*Nowa wersja LDTK-Smartive " + $version + "*")}},
    {type:"section", text:{type:"mrkdwn", text:"Dostępna jest nowa wersja edytora!"}},
    {type:"section", text:{type:"mrkdwn", text:("*Patch notes*\n\n" + $patch_notes)}},
    {type:"context", elements:[{type:"mrkdwn", text:"Windows · macOS · Linux"}]},
    {type:"actions", elements:[{
      type:"button", text:{type:"plain_text", text:"Pobierz aktualizację"},
      url:$url, style:"primary"
    }]}
  ]
}' > "$payload"

# curl's exit code checks HTTP status, and the response body confirms that
# Slack accepted the webhook. No silent successes or ignored failures.
response="$(curl --fail-with-body --silent --show-error --retry 3 \
  --connect-timeout 15 --max-time 60 \
  --request POST --header "Content-Type: application/json" \
  --data-binary "@$payload" "$SLACK_WEBHOOK_URL")"
if [[ "$response" != "ok" ]]; then
  echo "::error::Slack did not return the expected 'ok' response; notification unconfirmed." >&2
  exit 1
fi
echo "::notice::Slack accepted the announcement for $tag ($release_url)"
