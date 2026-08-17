#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: fix-dsh-tool-result-order.sh [OPTIONS]

Patch DSH's pi-ai and native DeepSeek history conversion so a tool result is
emitted only as a tool message. Without this patch, its text is also emitted
as an intervening user message, which strict APIs reject.

Options:
  --dsh-root PATH  Use the specified DSH installation root
  --check          Make no changes; fail if the target is unpatched
  --no-backup      Do not create a timestamped backup before patching
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
files=(
  "$dsh_root/node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js"
  "$dsh_root/node_modules/@deepseek-ai/dsh-llm-deepseek/lib/index.js"
)
olds=(
  $'\t\tconst text = flattenText(message);\n\t\tconst results = message.content.filter((block) => block.type === "tool-result");'
  $'\t\tconst toolResults = message.content.filter((block) => block.type === "tool-result");\n\t\tconst text = flattenText(message.content);'
)
news=(
  $'\t\tconst text = contentText(message.content.filter((block) => block.type !== "tool-result"));\n\t\tconst results = message.content.filter((block) => block.type === "tool-result");'
  $'\t\tconst toolResults = message.content.filter((block) => block.type === "tool-result");\n\t\tconst text = flattenText(message.content.filter((block) => block.type !== "tool-result"));'
)

for file in "${files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "error: target file does not exist: $file" >&2
    exit 1
  fi
done

state_of() {
  local file=$1
  local old=$2
  local new=$3
  OLD="$old" NEW="$new" node - "$file" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
const text = fs.readFileSync(file, 'utf8');
const count = (needle) => text.split(needle).length - 1;
const oldCount = count(process.env.OLD);
const newCount = count(process.env.NEW);
if (oldCount === 1 && newCount === 0) process.stdout.write('unpatched');
else if (oldCount === 0 && newCount === 1) process.stdout.write('patched');
else {
  console.error(`error: unexpected source shape in ${file} (old=${oldCount}, new=${newCount})`);
  process.exit(1);
}
NODE
}

patch_file() {
  local file=$1
  local old=$2
  local new=$3
  OLD="$old" NEW="$new" node - "$file" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
const text = fs.readFileSync(file, 'utf8');
const old = process.env.OLD;
const updated = text.replace(old, process.env.NEW);
if (updated === text || updated.includes(old)) {
  console.error(`error: safe replacement failed in ${file}`);
  process.exit(1);
}
fs.writeFileSync(file, updated);
NODE
}

echo "DSH root: $dsh_root"

unpatched=()
for i in "${!files[@]}"; do
  state=$(state_of "${files[$i]}" "${olds[$i]}" "${news[$i]}")
  if [[ "$state" == "unpatched" ]]; then
    unpatched+=("$i")
  fi
done

if $check_only; then
  if ((${#unpatched[@]})); then
    for i in "${unpatched[@]}"; do
      echo "unpatched: ${files[$i]}" >&2
    done
    exit 1
  fi
  echo "Tool-result ordering patch is installed for both adapters."
  exit 0
fi

if ((${#unpatched[@]})); then
  timestamp=$(date '+%Y%m%d-%H%M%S')
  for i in "${unpatched[@]}"; do
    file=${files[$i]}
    if $make_backup; then
      backup="$file.bak.$timestamp"
      cp -p -- "$file" "$backup"
      echo "Backup: $backup"
    fi
    patch_file "$file" "${olds[$i]}" "${news[$i]}"
    echo "Patched: $file"
  done
else
  echo "Both adapters were already patched; no changes made."
fi

for i in "${!files[@]}"; do
  file=${files[$i]}
  state=$(state_of "$file" "${olds[$i]}" "${news[$i]}")
  if [[ "$state" != "patched" ]]; then
    echo "error: post-operation verification failed: $file" >&2
    exit 1
  fi
  node --check "$file"
done

echo "Verification passed for both adapters. Restart DSH for the patch to take effect."
