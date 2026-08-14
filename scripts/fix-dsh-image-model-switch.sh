#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: fix-dsh-image-model-switch.sh [OPTIONS]

Patch DSH so sessions with historical images can switch to text-only models.
Historical image blocks are flattened to text placeholders on text-only model
requests instead of being sent upstream as image_url payloads or rejected by
text-only adapters.

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
  "$dsh_root/node_modules/@deepseek-ai/dsh-llm-pi-ai/lib/index.js"
  "$dsh_root/node_modules/@deepseek-ai/dsh-host-apiproxy/lib/index.js"
  "$dsh_root/node_modules/@deepseek-ai/dsh-host-apiproxy/lib/types/api-proxy.js"
  "$dsh_root/node_modules/@deepseek-ai/dsh-llm-deepseek/lib/index.js"
)
kinds=(piAi apiProxy apiProxyTypes deepseek)

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
    oldMarkers: ["pi-ai image conversion requires the durable attachment service"],
    verify: (value) => !value.includes("pi-ai image conversion requires the durable attachment service"),
    apply(value) {
      return value.replace(
        "\t\tif (contentHasImage(message.content)) throw new LlmError(\"pi-ai image conversion requires the durable attachment service\", \"UNSUPPORTED_CONTENT\");\n\t\tif (message.role === \"system\") {",
        "\t\tif (message.role === \"system\") {"
      );
    },
  },
  apiProxy: {
    oldMarkers: ["session already contains images", "messagesHaveImage", "contentHasImage"],
    verify: (value) => !value.includes("session already contains images") && !value.includes("messagesHaveImage") && !value.includes("contentHasImage"),
    apply(value) {
      value = value.replace(
        "\t\t\t\t\t\tif ([...found.agent.inbox.nextTurn, ...found.agent.inbox.nextStep].some((message) => contentHasImage(message.content)) || messagesHaveImage(found.agent.session.deriveMessages())) {\n\t\t\t\t\t\t\tconst info = await ctx.llm.resolveModelInfo(resolved.provider, resolved.model);\n\t\t\t\t\t\t\tif (info.inputModalities !== void 0 && !info.inputModalities.includes(\"image\")) return err(request, {\n\t\t\t\t\t\t\t\tcode: \"model-unavailable\",\n\t\t\t\t\t\t\t\tmessage: `Model \"${resolved.model}\" does not accept image input, but this session already contains images; select an image-capable model.`,\n\t\t\t\t\t\t\t\tdetails: {\n\t\t\t\t\t\t\t\t\tprovider,\n\t\t\t\t\t\t\t\t\tmodel\n\t\t\t\t\t\t\t\t}\n\t\t\t\t\t\t\t});\n\t\t\t\t\t\t}\n",
        ""
      );
      value = value.replace(
        "import { ReasoningEffortId, contentHasImage, createUserMessage, errorChain, freezeMessage } from \"@deepseek-ai/dsh-llm\";",
        "import { ReasoningEffortId, createUserMessage, errorChain, freezeMessage } from \"@deepseek-ai/dsh-llm\";"
      );
      value = value.replace(
        "/** True when the current model-visible surface contains an image. */\nfunction messagesHaveImage(messages) {\n\treturn messages.some((message) => contentHasImage(message.content));\n}\n",
        ""
      );
      return value;
    },
  },
  apiProxyTypes: {
    oldMarkers: ["session already contains images", "messagesHaveImage", "contentHasImage"],
    verify: (value) => !value.includes("session already contains images") && !value.includes("messagesHaveImage") && !value.includes("contentHasImage"),
    apply(value) {
      value = value.replace(
        "                        const pendingImage = [...found.agent.inbox.nextTurn, ...found.agent.inbox.nextStep]\n                            .some(message => contentHasImage(message.content));\n                        if (pendingImage || messagesHaveImage(found.agent.session.deriveMessages())) {\n                            const info = await ctx.llm.resolveModelInfo(resolved.provider, resolved.model);\n                            if (info.inputModalities !== undefined && !info.inputModalities.includes('image')) {\n                                return err(request, {\n                                    code: 'model-unavailable',\n                                    message: `Model \"${resolved.model}\" does not accept image input, but this session already contains images; select an image-capable model.`,\n                                    details: { provider, model },\n                                });\n                            }\n                        }\n",
        ""
      );
      value = value.replace(
        "import { contentHasImage, createUserMessage, freezeMessage, ReasoningEffortId } from '@deepseek-ai/dsh-llm';",
        "import { createUserMessage, freezeMessage, ReasoningEffortId } from '@deepseek-ai/dsh-llm';"
      );
      value = value.replace(
        "/** True when the current model-visible surface contains an image. */\nfunction messagesHaveImage(messages) {\n    return messages.some(message => contentHasImage(message.content));\n}\n",
        ""
      );
      return value;
    },
  },
  deepseek: {
    oldMarkers: ["does not support image content", "assertTextOnly", "contentHasImage"],
    verify: (value) => value.includes("Image omitted for text-only model") && !value.includes("does not support image content") && !value.includes("assertTextOnly") && !value.includes("contentHasImage"),
    apply(value) {
      value = value.replace(
        "import { CONTEXT_WINDOW_EXCEEDED_CODE, CallId, EMPTY_RESPONSE_CODE, LlmAdapter, LlmError, ProviderRequestId, QUOTA_EXCEEDED_CODE, ReasoningEffortId, RetryPolicySchema, assertUsableApiKey, attributionHeaders, contentHasImage, isContextWindowExceededError, isQuotaExceededError, resolveRetryPolicy } from \"@deepseek-ai/dsh-llm\";",
        "import { CONTEXT_WINDOW_EXCEEDED_CODE, CallId, EMPTY_RESPONSE_CODE, LlmAdapter, LlmError, ProviderRequestId, QUOTA_EXCEEDED_CODE, ReasoningEffortId, RetryPolicySchema, assertUsableApiKey, attributionHeaders, isContextWindowExceededError, isQuotaExceededError, resolveRetryPolicy } from \"@deepseek-ai/dsh-llm\";"
      );
      value = value.replace(
        "/** Join the text blocks of a message (used for user/tool-result content). */\nfunction flattenText(blocks) {\n\treturn blocks.filter((block) => block.type === \"text\").map((block) => block.text).join(\"\");\n}\n/** Reject core image content before any text-flattening path can silently erase it. */\nfunction assertTextOnly(blocks) {\n\tif (contentHasImage(blocks)) throw new LlmError(\"The DeepSeek chat-completions adapter does not support image content.\", \"UNSUPPORTED_CONTENT\");\n}\n",
        "/** Describe an image when the selected model cannot receive image bytes. */\nfunction imageText(block) {\n\tconst image = block.attachment;\n\tconst name = image.name === void 0 ? \"image\" : image.name;\n\treturn `[Image omitted for text-only model: ${name}, ${image.mediaType}, ${image.width}x${image.height}px, ${image.bytes} bytes]`;\n}\n/** Join model-visible text, preserving images as textual placeholders. */\nfunction flattenText(blocks) {\n\treturn blocks.map((block) => {\n\t\tswitch (block.type) {\n\t\t\tcase \"text\": return block.text;\n\t\t\tcase \"image\": return imageText(block);\n\t\t\tcase \"tool-result\": return flattenText(block.content);\n\t\t\tdefault: return \"\";\n\t\t}\n\t}).join(\"\");\n}\n"
      );
      value = value.replace("\t\tassertTextOnly(message.content);\n\t\tif (message.role === \"system\") {", "\t\tif (message.role === \"system\") {");
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
