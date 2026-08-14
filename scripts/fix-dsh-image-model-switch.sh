#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: fix-dsh-image-model-switch.sh [OPTIONS]

Patch DSH so sessions with historical images can switch to text-only models.
Historical image blocks are flattened to text placeholders on text-only model
requests instead of being sent upstream as image_url payloads.

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
llm_file="$dsh_root/node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js"
api_file="$dsh_root/node_modules/@deepseek-ai/dsh-host-apiproxy/lib/index.js"
api_types_file="$dsh_root/node_modules/@deepseek-ai/dsh-host-apiproxy/lib/types/api-proxy.js"
files=("$llm_file" "$api_file" "$api_types_file")

echo "DSH root: $dsh_root"

for file in "${files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "error: target file does not exist: $file" >&2
    exit 1
  fi
done

state_of() {
  local file=$1
  local kind=$2
  KIND="$kind" node - "$file" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
const kind = process.env.KIND;
const text = fs.readFileSync(file, 'utf8');
const count = (needle) => text.split(needle).length - 1;

const shapes = {
  llm: {
    old: '\t\tif (contentHasImage(message.content)) throw new LlmError("pi-ai image conversion requires the durable attachment service", "UNSUPPORTED_CONTENT");\n\t\tif (message.role === "system") {',
    new: '\t\tif (message.role === "system") {',
    verify() {
      return count(this.old) === 0 && count(this.new) >= 1;
    },
  },
  api: {
    old: '\t\t\t\t\t\tif ([...found.agent.inbox.nextTurn, ...found.agent.inbox.nextStep].some((message) => contentHasImage(message.content)) || messagesHaveImage(found.agent.session.deriveMessages())) {\n\t\t\t\t\t\t\tconst info = await ctx.llm.resolveModelInfo(resolved.provider, resolved.model);\n\t\t\t\t\t\t\tif (info.inputModalities !== void 0 && !info.inputModalities.includes("image")) return err(request, {\n\t\t\t\t\t\t\t\tcode: "model-unavailable",\n\t\t\t\t\t\t\t\tmessage: `Model "${resolved.model}" does not accept image input, but this session already contains images; select an image-capable model.`,\n\t\t\t\t\t\t\t\tdetails: {\n\t\t\t\t\t\t\t\t\tprovider,\n\t\t\t\t\t\t\t\t\tmodel\n\t\t\t\t\t\t\t\t}\n\t\t\t\t\t\t\t});\n\t\t\t\t\t\t}\n',
    new: '',
    verify() {
      return !text.includes('session already contains images') && !text.includes('messagesHaveImage') && !text.includes('contentHasImage');
    },
  },
  apiTypes: {
    old: '                        const pendingImage = [...found.agent.inbox.nextTurn, ...found.agent.inbox.nextStep]\n                            .some(message => contentHasImage(message.content));\n                        if (pendingImage || messagesHaveImage(found.agent.session.deriveMessages())) {\n                            const info = await ctx.llm.resolveModelInfo(resolved.provider, resolved.model);\n                            if (info.inputModalities !== undefined && !info.inputModalities.includes(\'image\')) {\n                                return err(request, {\n                                    code: \'model-unavailable\',\n                                    message: `Model "${resolved.model}" does not accept image input, but this session already contains images; select an image-capable model.`,\n                                    details: { provider, model },\n                                });\n                            }\n                        }\n',
    new: '',
    verify() {
      return !text.includes('session already contains images') && !text.includes('messagesHaveImage') && !text.includes('contentHasImage');
    },
  },
};

const shape = shapes[kind];
if (!shape) throw new Error(`unknown kind: ${kind}`);
const oldCount = shape.old.length === 0 ? 0 : count(shape.old);
const patched = shape.verify();
if (oldCount === 1 && !patched) process.stdout.write('unpatched');
else if (patched) process.stdout.write('patched');
else {
  console.error(`error: unexpected source shape in ${file} for ${kind} (old=${oldCount})`);
  process.exit(1);
}
NODE
}

patch_file() {
  local file=$1
  local kind=$2
  KIND="$kind" node - "$file" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
const kind = process.env.KIND;
let text = fs.readFileSync(file, 'utf8');

const replacements = {
  llm: [
    [
      '\t\tif (contentHasImage(message.content)) throw new LlmError("pi-ai image conversion requires the durable attachment service", "UNSUPPORTED_CONTENT");\n\t\tif (message.role === "system") {',
      '\t\tif (message.role === "system") {'
    ],
  ],
  api: [
    [
      '\t\t\t\t\t\tif ([...found.agent.inbox.nextTurn, ...found.agent.inbox.nextStep].some((message) => contentHasImage(message.content)) || messagesHaveImage(found.agent.session.deriveMessages())) {\n\t\t\t\t\t\t\tconst info = await ctx.llm.resolveModelInfo(resolved.provider, resolved.model);\n\t\t\t\t\t\t\tif (info.inputModalities !== void 0 && !info.inputModalities.includes("image")) return err(request, {\n\t\t\t\t\t\t\t\tcode: "model-unavailable",\n\t\t\t\t\t\t\t\tmessage: `Model "${resolved.model}" does not accept image input, but this session already contains images; select an image-capable model.`,\n\t\t\t\t\t\t\t\tdetails: {\n\t\t\t\t\t\t\t\t\tprovider,\n\t\t\t\t\t\t\t\t\tmodel\n\t\t\t\t\t\t\t\t}\n\t\t\t\t\t\t\t});\n\t\t\t\t\t\t}\n',
      ''
    ],
    ['import { ReasoningEffortId, contentHasImage, createUserMessage, errorChain, freezeMessage } from "@deepseek-ai/dsh-llm";', 'import { ReasoningEffortId, createUserMessage, errorChain, freezeMessage } from "@deepseek-ai/dsh-llm";'],
    ['/** True when the current model-visible surface contains an image. */\nfunction messagesHaveImage(messages) {\n\treturn messages.some((message) => contentHasImage(message.content));\n}\n', ''],
  ],
  apiTypes: [
    [
      '                        const pendingImage = [...found.agent.inbox.nextTurn, ...found.agent.inbox.nextStep]\n                            .some(message => contentHasImage(message.content));\n                        if (pendingImage || messagesHaveImage(found.agent.session.deriveMessages())) {\n                            const info = await ctx.llm.resolveModelInfo(resolved.provider, resolved.model);\n                            if (info.inputModalities !== undefined && !info.inputModalities.includes(\'image\')) {\n                                return err(request, {\n                                    code: \'model-unavailable\',\n                                    message: `Model "${resolved.model}" does not accept image input, but this session already contains images; select an image-capable model.`,\n                                    details: { provider, model },\n                                });\n                            }\n                        }\n',
      ''
    ],
    ["import { contentHasImage, createUserMessage, freezeMessage, ReasoningEffortId } from '@deepseek-ai/dsh-llm';", "import { createUserMessage, freezeMessage, ReasoningEffortId } from '@deepseek-ai/dsh-llm';"],
    ['/** True when the current model-visible surface contains an image. */\nfunction messagesHaveImage(messages) {\n    return messages.some(message => contentHasImage(message.content));\n}\n', ''],
  ],
};

for (const [oldText, newText] of replacements[kind] ?? []) {
  if (text.includes(oldText)) text = text.replace(oldText, newText);
}
fs.writeFileSync(file, text);
NODE
}

kinds=(llm api apiTypes)
unpatched=()
for i in "${!files[@]}"; do
  state=$(state_of "${files[$i]}" "${kinds[$i]}")
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
  echo "All targets are patched."
else
  if ((${#unpatched[@]})); then
    timestamp=$(date '+%Y%m%d-%H%M%S')
    for i in "${unpatched[@]}"; do
      file=${files[$i]}
      kind=${kinds[$i]}
      if $make_backup; then
        backup="$file.bak.$timestamp"
        cp -p -- "$file" "$backup"
        echo "Backup: $backup"
      fi
      patch_file "$file" "$kind"
      echo "Patched: $file"
    done
  else
    echo "All targets were already patched; no changes made."
  fi
fi

for i in "${!files[@]}"; do
  file=${files[$i]}
  kind=${kinds[$i]}
  state=$(state_of "$file" "$kind")
  if [[ "$state" != "patched" ]]; then
    echo "error: post-operation verification failed: $file" >&2
    exit 1
  fi
  node --check "$file"
done

echo "Verification passed for all targets."
if ! $check_only && ((${#unpatched[@]})); then
  echo "Restart DSH for the image model-switch patch to take effect."
fi
