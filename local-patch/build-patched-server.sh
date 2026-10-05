#!/usr/bin/env bash
# Rebuilds out/server.asar: the installed T3 Code server.asar with apps/server/dist replaced by
# this worktree's build. Run from Git Bash after moving the branch onto the installed release.
set -euo pipefail

WT="$(cd "$(dirname "$0")/.." && pwd)"
LP="$WT/local-patch"
RES="$LOCALAPPDATA/Programs/t3code/resources"
SRC_ASAR="$RES/server.asar"
[ -f "$RES/server.asar.original" ] && SRC_ASAR="$RES/server.asar.original" # patch already installed
ASAR_LIB="file:///$(cygpath -m "$(ls -d "$WT"/node_modules/.pnpm/@electron+asar@4.*/node_modules/@electron/asar | tail -1)")/lib/asar.js"

asar() { (cd "$WT" && node --input-type=module -e "import * as a from '$ASAR_LIB'; $1" "${@:2}"); }

echo "== Extracting installed server.asar"
rm -rf "$LP/installed" "$LP/stage" "$LP/out"
asar "a.extractAll(process.argv[1], process.argv[2])" "$(cygpath -w "$SRC_ASAR")" "$(cygpath -w "$LP/installed")"
OLD="$LP/installed/apps/server/dist"

VERSION="$(node -p "require(process.argv[1]).version" "$(cygpath -w "$LP/installed/package.json")")"
COMMIT="$(asar "console.log(JSON.parse(a.extractFile(process.argv[1], 'package.json')).t3codeCommitHash)" "$(cygpath -w "$RES/app.asar")")"
echo "Installed: v$VERSION (commit $COMMIT)"
if ! git -C "$WT" merge-base --is-ancestor "$COMMIT" HEAD 2>/dev/null; then
  echo "WARNING: HEAD is not based on the installed commit $COMMIT. Rebase the branch onto it first." >&2
  exit 1
fi

# Public build-time values ship inside the installed client bundle; reuse them so sign-in and relay match.
read_env() { grep -ohE "$1:\`[^\`]*\`" "$OLD"/client/assets/*.js | head -1 | sed -E "s/^$1:\`(.*)\`$/\1/"; }
export CI=true APP_VERSION="$VERSION"
for k in VITE_CLERK_PUBLISHABLE_KEY VITE_CLERK_JWT_TEMPLATE VITE_CLERK_CLI_OAUTH_CLIENT_ID VITE_T3CODE_RELAY_URL \
         VITE_RELAY_OTLP_TRACES_URL VITE_RELAY_OTLP_TRACES_DATASET VITE_RELAY_OTLP_TRACES_TOKEN; do
  export "$k=$(read_env "$k")"
done
export T3CODE_CLERK_PUBLISHABLE_KEY="$VITE_CLERK_PUBLISHABLE_KEY" T3CODE_CLERK_CLI_OAUTH_CLIENT_ID="$VITE_CLERK_CLI_OAUTH_CLIENT_ID" \
  T3CODE_RELAY_URL="$VITE_T3CODE_RELAY_URL" T3CODE_RELAY_CLIENT_OTLP_TRACES_URL="$VITE_RELAY_OTLP_TRACES_URL" \
  T3CODE_RELAY_CLIENT_OTLP_TRACES_DATASET="$VITE_RELAY_OTLP_TRACES_DATASET" T3CODE_RELAY_CLIENT_OTLP_TRACES_TOKEN="$VITE_RELAY_OTLP_TRACES_TOKEN"

echo "== Building v$VERSION"
cd "$WT"
pnpm install --frozen-lockfile >/dev/null
node scripts/update-release-package-versions.ts "$VERSION" >/dev/null
trap 'git -C "$WT" checkout -- "*package.json" pnpm-lock.yaml' EXIT
rm -rf apps/server/dist apps/web/dist
pnpm run build:desktop > "$LP/build.log" 2>&1 || { echo "Build failed; see $LP/build.log" >&2; exit 1; }

echo "== Staging and packing"
cp -a "$LP/installed" "$LP/stage"
rm -rf "$LP/stage/apps/server/dist" && mkdir -p "$LP/stage/apps/server/dist"
(cd apps/server/dist && tar cf - --exclude='*.map' --exclude='./client/.vite' .) | (cd "$LP/stage/apps/server/dist" && tar xf -)
for f in favicon.ico apple-touch-icon.png favicon-32x32.png favicon-16x16.png; do cp "$OLD/client/$f" "$LP/stage/apps/server/dist/client/$f"; done
# Same unpack glob as scripts/build-desktop-artifact.ts. The stage must not sit under a dot-directory.
asar "await a.createPackageWithOptions(process.argv[1], process.argv[2], { dot: true,
  unpack: '{**/*.node,**/*.dll,**/*.exe,**/*.so,**/*.so.*,**/*.dylib}', globOptions: { cwd: process.argv[1] } })" \
  "$(cygpath -w "$LP/stage")" "$(cygpath -w "$LP/out/server.asar")"
diff <(cd "$LP/out/server.asar.unpacked" && find . -type f | sort) <(cd "$RES/server.asar.unpacked" && find . -type f | sort) \
  || { echo "Unpacked native files differ from the install; not safe to swap." >&2; exit 1; }
rm -rf "$LP/installed" "$LP/stage"
echo "Ready: $LP/out/server.asar. Quit T3 Code, then run Install-PatchedServer.ps1."
