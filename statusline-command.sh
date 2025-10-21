#!/bin/bash

# Read JSON input
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')

# Calculate token usage with 3-hour resets at 15, 18, 21, 00, 03, 06, 09, 12 UTC
# Get current hour in UTC
current_hour=$(date -u +"%H")
current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Calculate the most recent reset hour (15, 18, 21, 00, 03, 06, 09, 12)
# Start from 15 and go in 3-hour intervals
reset_hours=(0 3 6 9 12 15 18 21)
reset_hour=0

for hour in "${reset_hours[@]}"; do
    if [ "$current_hour" -ge "$hour" ]; then
        reset_hour=$hour
    fi
done

# Get cutoff time for current reset period
cutoff_time=$(date -u +"%Y-%m-%d")T$(printf "%02d" $reset_hour):00:00Z

# If calculated cutoff is in the future, use the previous reset period
if [[ "$current_time" < "$cutoff_time" ]]; then
    # Go back one period (3 hours or previous day)
    if [ "$reset_hour" -eq 0 ]; then
        cutoff_time=$(date -u -v-1d +"%Y-%m-%d")T21:00:00Z
    else
        prev_hour=$((reset_hour - 3))
        cutoff_time=$(date -u +"%Y-%m-%d")T$(printf "%02d" $prev_hour):00:00Z
    fi
fi

# Create a temporary file for accumulation
tmpfile=$(mktemp)

# Find all JSONL files modified in the last 24 hours and extract all tokens with model info
# Model-specific weighting: Haiku=1x input/5x output, Sonnet=3x input/15x output, Opus=15x input/75x output
find ./claude/projects ~/.claude/projects -name "*.jsonl" -type f -mtime -1 2>/dev/null | while read -r file; do
    jq -r --arg cutoff "$cutoff_time" '
        select(.message.usage and .timestamp > $cutoff) |
        if (.message.model // .model | test("opus")) then
          "opus:" + (((.message.usage.input_tokens // 0) * 15) + ((.message.usage.output_tokens // 0) * 75) | tostring)
        elif (.message.model // .model | test("sonnet")) then
          "sonnet:" + (((.message.usage.input_tokens // 0) * 3) + ((.message.usage.output_tokens // 0) * 15) | tostring)
        else
          "haiku:" + (((.message.usage.input_tokens // 0) * 1) + ((.message.usage.output_tokens // 0) * 5) | tostring)
        end
    ' "$file" 2>/dev/null >> "$tmpfile"
done

# Parse model-specific totals
opus_tokens=0
sonnet_tokens=0
haiku_tokens=0
total_tokens=0

while IFS=: read -r model_name tokens; do
    if [ -z "$tokens" ]; then continue; fi
    tokens=$(printf "%.0f" "$tokens" 2>/dev/null || echo 0)
    total_tokens=$((total_tokens + tokens))
    case "$model_name" in
        opus) opus_tokens=$((opus_tokens + tokens)) ;;
        sonnet) sonnet_tokens=$((sonnet_tokens + tokens)) ;;
        haiku) haiku_tokens=$((haiku_tokens + tokens)) ;;
    esac
done < "$tmpfile"

rm -f "$tmpfile"

# If no tokens found, set to 0
if [ -z "$total_tokens" ] || [ "$total_tokens" = "" ]; then
    total_tokens=0
fi

# Max tokens per 3-hour period
# Based on actual Claude limits with model-specific weighting: ~2M weighted tokens per 3-hour period
token_limit=2000000

# Calculate percentage of 3-hour period limit
if [ "$total_tokens" -gt 0 ] && [ "$token_limit" -gt 0 ]; then
    usage_pct=$(awk "BEGIN {printf \"%.0f\", ($total_tokens / $token_limit) * 100}")

    # Format model tokens
    format_model_tokens() {
        local tokens=$1
        if [ "$tokens" -ge 1000000 ]; then
            awk "BEGIN {printf \"%.1fM\", $tokens / 1000000}" | sed 's/\.0M$/M/'
        elif [ "$tokens" -ge 1000 ]; then
            awk "BEGIN {printf \"%.0fK\", $tokens / 1000}"
        else
            echo "$tokens"
        fi
    }

    opus_display=$(format_model_tokens $opus_tokens)
    sonnet_display=$(format_model_tokens $sonnet_tokens)
    haiku_display=$(format_model_tokens $haiku_tokens)

    # Format: show tokens + percentage + model breakdown
    if [ "$total_tokens" -ge 1000000 ]; then
        tokens_display=$(awk "BEGIN {printf \"%.1f\", $total_tokens / 1000000}" | sed 's/\.0$//')
        usage_display="${tokens_display}M/${usage_pct}% (O:$opus_display S:$sonnet_display H:$haiku_display)"
    elif [ "$total_tokens" -ge 1000 ]; then
        tokens_display=$(awk "BEGIN {printf \"%.0f\", $total_tokens / 1000}")
        usage_display="${tokens_display}K/${usage_pct}% (O:$opus_display S:$sonnet_display H:$haiku_display)"
    else
        usage_display="${total_tokens}/${usage_pct}% (O:$opus_display S:$sonnet_display H:$haiku_display)"
    fi
else
    usage_display="0/0%"
fi

# Change to the working directory
cd "$cwd" 2>/dev/null || cwd="$HOME"

# Get current directory with ~ substitution
current_dir="${cwd/#$HOME/~}"

# Git information
git_info=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
        # Check if repo is dirty (skip optional locks to avoid blocking)
        if git --no-optional-locks diff --quiet 2>/dev/null && git --no-optional-locks diff --cached --quiet 2>/dev/null; then
            # Clean repo
            git_info=$(printf " \033[1;34mgit:(\033[0;31m%s\033[1;34m)\033[0m" "$branch")
        else
            # Dirty repo
            git_info=$(printf " \033[1;34mgit:(\033[0;31m%s\033[1;34m)\033[0m \033[0;33m✗\033[0m" "$branch")
        fi
    fi
fi

# Print the status line (green arrow + cyan directory + git info + model + token usage)
printf "\033[1;32m➜\033[0m  \033[0;36m%s\033[0m%s \033[0;35m[%s]\033[0m \033[0;33m%s\033[0m" "$current_dir" "$git_info" "$model" "$usage_display"
