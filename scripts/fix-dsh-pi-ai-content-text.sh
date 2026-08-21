#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: fix-dsh-pi-ai-content-text.sh [OPTIONS]

Patch DSH so pi-ai-backed (custom) models stop failing with
"contentText is not defined". The published @deepseek-ai/dsh-llm-pi-ai
package calls contentText() in its text-only context conversion but never
imports it from @earendil-works/pi-ai; this patch adds the missing import.

Options:
  --dsh-root PATH  Use the specified DSH installation root
  --check          Make no changes; fail if any target is unpatched
  --no-backup      Do not create timestamped backups before patching
  --help           Show this help
EOF
}

dsh_root=""
check_only=false
make_backup=true

while (($#)); do
  case "$1" in
    --dsh-root)
      if (($# < 2)) || [[ -z "$2" ]]; then
        echo "error: --dsh-root requires a path" >&2
        exit 2
      fi
      dsh_root=$2
      shift 2
      ;;
    --check)
      check_only=true
      shift
      ;;
    --no-backup)
      make_backup=false
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$dsh_root" ]]; then
  npm_cache=${npm_config_cache:-"$HOME/.npm"}
  search_root="$npm_cache/_npx"
  if [[ ! -d "$search_root" ]]; then
    echo "error: DSH search directory does not exist: $search_root" >&2
    exit 1
  fi

  match=$(find "$search_root" -type f -path '*/node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js' -print 2>/dev/null | LC_ALL=C sort | tail -n 1)
  if [[ -z "$match" ]]; then
    echo "error: could not discover DSH under: $search_root" >&2
    exit 1
  fi
  dsh_root=${match%/node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js}
fi

dsh_root=${dsh_root%/}
file="$dsh_root/node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js"

echo "DSH root: $dsh_root"

if [[ ! -f "$file" ]]; then
  echo "error: target file does not exist: $file" >&2
  exit 1
fi

node_patch=""
IFS= read -r -d '' node_patch <<'NODE' || true
const fs = require("fs");
const file = process.argv[1];
const mode = process.env.MODE;
let text = fs.readFileSync(file, "utf8");

const piAiImportPattern = /^import \{([^}]*)\} from (["'])@earendil-works\/pi-ai\2;$/m;
const callMarker = "contentText(message.content.filter((block) => block.type !== \"tool-result\"))";

function hasPiAiImport(value, name) {
  const match = value.match(piAiImportPattern);
  return match !== null && match[1].split(",").some((item) => item.trim() === name);
}

function verify(value) {
  return value.includes(callMarker) && hasPiAiImport(value, "contentText");
}

if (mode === "state") {
  if (verify(text)) {
    process.stdout.write("patched");
  } else if (text.includes(callMarker)) {
    process.stdout.write("unpatched");
  } else {
    console.error(`error: unexpected source shape in ${file}`);
    process.exit(1);
  }
} else if (mode === "patch") {
  if (!hasPiAiImport(text, "contentText")) {
    if (!piAiImportPattern.test(text)) {
      console.error(`error: cannot locate the @earendil-works/pi-ai import in ${file}`);
      process.exit(1);
    }
    text = text.replace(piAiImportPattern, (statement, imports, quote) => {
      return `import { contentText, ${imports.trim()} } from ${quote}@earendil-works/pi-ai${quote};`;
    });
  }
  fs.writeFileSync(file, text);
  if (!verify(text)) {
    console.error(`error: patch did not reach expected state in ${file}`);
    process.exit(1);
  }
} else {
  console.error(`error: unknown mode: ${mode}`);
  process.exit(2);
}
NODE

state_of() {
  local file=$1
  MODE=state node -e "$node_patch" "$file"
}

patch_file() {
  local file=$1
  MODE=patch node -e "$node_patch" "$file"
}

state=$(state_of "$file")
if [[ "$state" == "unpatched" ]]; then
  if $check_only; then
    echo "unpatched: $file" >&2
    exit 1
  fi
  if $make_backup; then
    timestamp=$(date '+%Y%m%d-%H%M%S')
    backup="$file.bak.$timestamp"
    cp -p -- "$file" "$backup"
    echo "Backup: $backup"
  fi
  patch_file "$file"
  echo "Patched: $file"
else
  echo "Target was already patched; no changes made."
fi

state=$(state_of "$file")
if [[ "$state" != "patched" ]]; then
  echo "error: post-operation verification failed: $file" >&2
  exit 1
fi
node --check "$file"

echo "Verification passed."
if ! $check_only && [[ "$state" == "unpatched" ]]; then
  echo "Restart DSH for the pi-ai contentText patch to take effect."
fi
