#!/usr/bin/env bash
# Proves Hisaab's privacy claim against the built artifact rather than the
# source, which is the only place the claim is actually true or false.
# See spec-27 dec-10 and ac-36.
#
# Usage: tool/verify_offline.sh
# Needs a release build to exist. Run `flutter build apk --release` first.
set -euo pipefail
cd "$(dirname "$0")/.."

manifest=$(find build/app/intermediates -path '*merged_manifest*release*' \
  -name 'AndroidManifest.xml' 2>/dev/null | head -1)

if [[ -z "$manifest" ]]; then
  echo "FAIL: no merged release manifest found. Run: flutter build apk --release"
  exit 1
fi

echo "Checking $manifest"
fails=0

if grep -q 'android:name="android.permission.INTERNET"' "$manifest"; then
  echo "FAIL: the release manifest declares INTERNET"
  fails=$((fails + 1))
else
  echo "ok: no INTERNET permission"
fi

declared=$(grep -o 'android:name="android.permission[^"]*"' "$manifest" || true)
if [[ -n "$declared" ]]; then
  echo "note: the release build declares these permissions:"
  echo "$declared" | sed 's/^/      /'
else
  echo "ok: the release build declares no permissions at all"
fi

for attr in 'android:allowBackup="false"' \
            'android:fullBackupContent="false"' \
            'android:dataExtractionRules="@xml/data_extraction_rules"'; do
  if grep -q "$attr" "$manifest"; then
    echo "ok: $attr"
  else
    echo "FAIL: missing $attr"
    fails=$((fails + 1))
  fi
done

if [[ $fails -gt 0 ]]; then
  echo
  echo "$fails check(s) failed. The README's privacy claim is currently false."
  exit 1
fi

echo
echo "All checks passed. Nothing leaves the phone unless the user shares it."
