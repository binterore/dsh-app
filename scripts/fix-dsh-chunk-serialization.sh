#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: fix-dsh-chunk-serialization.sh [OPTIONS]

Patch DSH so assistant/chunk session events never carry non-JSON-serializable
data. Some OpenAI-compatible gateways emit `response.reasoning_summary_text.delta`
(and similar) SSE events without a `delta` field; pi-ai then appends the literal
"undefined" to the thinking text and forwards an undefined delta, which
dsh-llm-pi-ai's toStreamChunks places verbatim into the assistant/chunk event.
The session's lossless-JSON boundary then rejects the event with
`session event "assistant/chunk" carries non-JSON-serializable data`, aborting
the turn.

The patch:
- pi-ai (openai-responses-shared.js): treat a missing delta as "" instead of
  appending "undefined" / emitting undefined deltas.
- dsh-llm-pi-ai (lib/index.js): normalize every chunk field at the adapter
  boundary (text, content, argumentsDelta, tool-call name/arguments, usage
  counts) so a provider can never put an undefined value into a session event.

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
files=(
  "$dsh_root/node_modules/@earendil-works/pi-ai/dist/api/openai-responses-shared.js"
  "$dsh_root/node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js"
)
kinds=(piAi adapter)

echo "DSH root: $dsh_root"

for file in "${files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "error: target file does not exist: $file" >&2
    exit 1
  fi
done

node_patch='const fs = require("fs");
const file = process.argv[1];
const kind = process.env.KIND;
const mode = process.env.MODE;
let text = fs.readFileSync(file, "utf8");

const patches = {
  piAi: {
    // Root cause: a gateway may send reasoning/text deltas without a delta
    // field. Guard every accumulation and every emitted event.
    oldMarkers: [
      "slot.block.thinking += event.delta;",
      "slot.block.text += event.delta;",
      "slot.block.partialJson += event.delta;",
      "delta: event.delta,",
      "pushToolCallDelta(slot, event.delta);",
    ],
    verify: (value) =>
      !value.includes("slot.block.thinking += event.delta;") &&
      !value.includes("slot.block.text += event.delta;") &&
      !value.includes("slot.block.partialJson += event.delta;") &&
      !value.includes("delta: event.delta,") &&
      !value.includes("pushToolCallDelta(slot, event.delta);"),
    apply(value) {
      value = value.split("slot.block.thinking += event.delta;").join("slot.block.thinking += event.delta ?? \"\";");
      value = value.split("slot.block.text += event.delta;").join("slot.block.text += event.delta ?? \"\";");
      value = value.split("slot.block.partialJson += event.delta;").join("slot.block.partialJson += event.delta ?? \"\";");
      value = value.split("delta: event.delta,").join("delta: event.delta ?? \"\",");
      value = value.split("pushToolCallDelta(slot, event.delta);").join("pushToolCallDelta(slot, event.delta ?? \"\");");
      return value;
    },
  },
  adapter: {
    // Adapter boundary: an assistant/chunk event must be losslessly
    // JSON-serializable no matter what the provider stream carries.
    oldMarkers: [
      "text: event.delta\n",
      "text: event.content\n",
      "argumentsDelta: event.delta\n",
      "name: event.toolCall.name,\n",
      "arguments: JSON.stringify(event.toolCall.arguments)\n",
      "inputTokens: usage.input,\n",
      "outputTokens: usage.output,\n",
      "thoughtSignature: block.thoughtSignature }\n\t\t\t\t};\n\t\t\t}\n\t\t})",
    ],
    verify: (value) =>
      !value.includes("text: event.delta\n") &&
      !value.includes("text: event.content\n") &&
      !value.includes("argumentsDelta: event.delta\n") &&
      !value.includes("name: event.toolCall.name,\n") &&
      !value.includes("arguments: JSON.stringify(event.toolCall.arguments)\n") &&
      !value.includes("inputTokens: usage.input,\n") &&
      !value.includes("outputTokens: usage.output,\n") &&
      value.includes("}).filter((block) => block !== void 0)"),
    apply(value) {
      value = value.split("text: event.delta\n").join("text: event.delta ?? \"\"\n");
      value = value.split("text: event.content\n").join("text: event.content ?? \"\"\n");
      value = value.split("argumentsDelta: event.delta\n").join("argumentsDelta: event.delta ?? \"\"\n");
      value = value.split("name: event.toolCall.name,\n").join("name: event.toolCall.name ?? \"\",\n");
      value = value.split("arguments: JSON.stringify(event.toolCall.arguments)\n").join("arguments: JSON.stringify(event.toolCall.arguments ?? {})\n");
      value = value.split("inputTokens: usage.input,\n").join("inputTokens: usage.input ?? 0,\n");
      value = value.split("outputTokens: usage.output,\n").join("outputTokens: usage.output ?? 0,\n");
      value = value.split("thoughtSignature: block.thoughtSignature }\n\t\t\t\t};\n\t\t\t}\n\t\t})").join("thoughtSignature: block.thoughtSignature }\n\t\t\t\t};\n\t\t\t}\n\t\t}).filter((block) => block !== void 0)");
      return value;
    },
  },
};

const patch = patches[kind];
if (!patch) {
  console.error(`error: unknown patch kind: ${kind}`);
  process.exit(2);
}

if (mode === "state") {
  if (patch.verify(text)) {
    process.stdout.write("patched");
  } else if (patch.oldMarkers.some((marker) => text.includes(marker))) {
    process.stdout.write("unpatched");
  } else {
    console.error(`error: unexpected source shape in ${file} for ${kind}`);
    process.exit(1);
  }
} else if (mode === "patch") {
  text = patch.apply(text);
  fs.writeFileSync(file, text);
  if (!patch.verify(text)) {
    console.error(`error: patch did not reach expected state in ${file} for ${kind}`);
    process.exit(1);
  }
} else {
  console.error(`error: unknown mode: ${mode}`);
  process.exit(2);
}
'

state_of() {
  local file=$1
  local kind=$2
  MODE=state KIND="$kind" node -e "$node_patch" "$file"
}

patch_file() {
  local file=$1
  local kind=$2
  MODE=patch KIND="$kind" node -e "$node_patch" "$file"
}

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
  echo "Chunk-serialization patch is installed for pi-ai and dsh-llm-pi-ai."
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
    patch_file "$file" "${kinds[$i]}"
    echo "Patched: $file"
  done
else
  echo "Both targets were already patched; no changes made."
fi

for i in "${!files[@]}"; do
  file=${files[$i]}
  state=$(state_of "$file" "${kinds[$i]}")
  if [[ "$state" != "patched" ]]; then
    echo "error: post-operation verification failed: $file" >&2
    exit 1
  fi
  node --check "$file"
done

echo "Verification passed for both targets. Restart DSH for the patch to take effect."
