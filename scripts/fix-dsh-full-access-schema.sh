#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: fix-dsh-full-access-schema.sh [OPTIONS]

Patch DSH shell-tool schemas so danger-full-access does not advertise an
invalid escalation target.

Options:
  --dsh-root PATH  Use the specified DSH installation root
  --check          Make no changes; fail if either target is unpatched
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

  match=$(find "$search_root" -type f -path '*/node_modules/@deepseek-ai/dsh-tool-bash/lib/index.js' -print 2>/dev/null | LC_ALL=C sort | tail -n 1)
  if [[ -z "$match" ]]; then
    echo "error: could not discover DSH under: $search_root" >&2
    exit 1
  fi
  dsh_root=${match%/node_modules/@deepseek-ai/dsh-tool-bash/lib/index.js}
fi

dsh_root=${dsh_root%/}
files=(
  "$dsh_root/node_modules/@deepseek-ai/dsh-tool-bash/lib/index.js"
  "$dsh_root/node_modules/@deepseek-ai/dsh-tool-pwsh/lib/index.js"
)
old='const escalationModes = defaultMode === void 0 ? [] : ESCALATION_TARGETS;'
new='const escalationModes = defaultMode === void 0 || defaultMode === "danger-full-access" ? [] : ESCALATION_TARGETS;'

echo "DSH root: $dsh_root"

unpatched=()
for file in "${files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "error: target file does not exist: $file" >&2
    exit 1
  fi

  state=$(OLD="$old" NEW="$new" node - "$file" <<'NODE'
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
  )
  if [[ "$state" == "unpatched" ]]; then
    unpatched+=("$file")
  fi
done

if $check_only; then
  if ((${#unpatched[@]})); then
    for file in "${unpatched[@]}"; do
      echo "unpatched: $file" >&2
    done
    exit 1
  fi
  echo "Both targets are patched."
else
  if ((${#unpatched[@]})); then
    timestamp=$(date '+%Y%m%d-%H%M%S')
    for file in "${unpatched[@]}"; do
      if $make_backup; then
        backup="$file.bak.$timestamp"
        cp -p -- "$file" "$backup"
        echo "Backup: $backup"
      fi
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
      echo "Patched: $file"
    done
  else
    echo "Both targets were already patched; no changes made."
  fi
fi

for file in "${files[@]}"; do
  OLD="$old" NEW="$new" node - "$file" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
const text = fs.readFileSync(file, 'utf8');
const count = (needle) => text.split(needle).length - 1;
if (count(process.env.OLD) !== 0 || count(process.env.NEW) !== 1) {
  console.error(`error: post-operation verification failed: ${file}`);
  process.exit(1);
}
NODE
  node --check "$file"
done

echo "Verification passed for both targets."
if ! $check_only && ((${#unpatched[@]})); then
  echo "Restart DSH for the patched schema to take effect."
fi
