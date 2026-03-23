#!/bin/bash
set -euo pipefail

# Generate a Sparkle appcast.xml for a single release.
# Usage: generate-appcast-entry.sh <version> <zip-path> <download-url> <ed-signature>

VERSION="${1:?Usage: $0 <version> <zip-path> <download-url> <ed-signature>}"
ZIP_PATH="${2:?Missing zip path}"
DOWNLOAD_URL="${3:?Missing download URL}"
ED_SIGNATURE="${4:?Missing EdDSA signature}"

FILESIZE=$(stat -f%z "$ZIP_PATH" 2>/dev/null || stat --printf="%s" "$ZIP_PATH")
PUBDATE=$(date -R 2>/dev/null || date "+%a, %d %b %Y %H:%M:%S %z")

cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Gitbox</title>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <enclosure
        url="${DOWNLOAD_URL}"
        length="${FILESIZE}"
        type="application/octet-stream"
        sparkle:edSignature="${ED_SIGNATURE}" />
    </item>
  </channel>
</rss>
EOF
