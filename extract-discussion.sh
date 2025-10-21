#!/bin/bash

# Find the discussion with the most recent user message
# Extract messages and filter out tool uses
# Usage: extract_discussion.sh [--thinking]

# Check for --thinking flag
INCLUDE_THINKING=false
if [[ "$1" == "--thinking" ]] || [[ "$1" == "-t" ]]; then
    INCLUDE_THINKING=true
fi

# Search paths
SEARCH_PATHS=("$HOME/.claude/projects" "./.claude/projects")

# Helper function to check if file has meaningful assistant content
# (more than just the warmup response)
has_assistant_content() {
    local file="$1"
    local count=$(jq -r '
        select(.type == "assistant") |
        .content = (
            if .message.content | type == "array" then
                [.message.content[] |
                    select(
                        (.type != "tool_use" or (.name != "Bash" and .name != "Grep" and .name != "Glob" and .name != "Read" and .name != "Task" and .name != "Edit" and .name != "Write")) and
                        .type != "tool_result"
                    )
                ]
            else
                .message.content
            end
        ) |
        (
            if .content | type == "array" then
                (.content | map(
                    if .type == "text" then .text
                    else ""
                    end
                ) | join(""))
            else
                .content
            end
        ) |
        select(length > 0)
    ' "$file" 2>/dev/null | wc -l | tr -d ' ')

    # Need at least 2 assistant messages (more than just warmup response)
    if [ "$count" -ge 2 ]; then
        echo "yes"
    fi
}

# Find all .jsonl files and the most recent user message with assistant content
MOST_RECENT_FILE=""
MOST_RECENT_TIME=""

for BASE_PATH in "${SEARCH_PATHS[@]}"; do
    if [ ! -d "$BASE_PATH" ]; then
        continue
    fi

    while IFS= read -r file; do
        # Check if file has assistant content first
        if [ -z "$(has_assistant_content "$file")" ]; then
            continue
        fi

        # Count non-warmup user messages (need at least 2: warmup + actual message)
        USER_MSG_COUNT=$(jq -r 'select(.type == "user") | .message.content' "$file" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$USER_MSG_COUNT" -lt 3 ]; then
            continue
        fi

        # Find most recent user message timestamp in this file
        TIMESTAMP=$(jq -r 'select(.type == "user") | .timestamp' "$file" 2>/dev/null | tail -1)

        if [ -n "$TIMESTAMP" ] && [ "$TIMESTAMP" != "null" ]; then
            if [ -z "$MOST_RECENT_TIME" ] || [[ "$TIMESTAMP" > "$MOST_RECENT_TIME" ]]; then
                MOST_RECENT_TIME="$TIMESTAMP"
                MOST_RECENT_FILE="$file"
            fi
        fi
    done < <(find "$BASE_PATH" -name "*.jsonl" 2>/dev/null)
done

if [ -z "$MOST_RECENT_FILE" ]; then
    echo "No discussion files with assistant responses found."
    exit 1
fi

# Create temporary file
TMPFILE=$(mktemp)

# Extract and format messages, skipping empty ones
jq -r --argjson include_thinking "$INCLUDE_THINKING" '
    select(.type == "user" or .type == "assistant") |

    # Extract basic info
    {
        role: .message.role,
        content: .message.content
    } |

    # Filter content to remove tool uses and tool results
    .content = (
        if .content | type == "array" then
            [.content[] |
                select(
                    (.type != "tool_use" or (.name != "Bash" and .name != "Grep" and .name != "Glob" and .name != "Read" and .name != "Task" and .name != "Edit" and .name != "Write")) and
                    .type != "tool_result"
                )
            ]
        else
            .content
        end
    ) |

    # Build the text content
    (
        if .content | type == "array" then
            (.content | map(
                if .type == "text" then .text
                elif .type == "thinking" and $include_thinking then "[THINKING]\n" + .thinking + "\n[/THINKING]"
                else ""
                end
            ) | join("\n"))
        else
            .content
        end
    ) as $text |

    # Only output if there is actual content
    if ($text | length) > 0 then
        ((.role | ascii_upcase) + ":\n" + $text + "\n")
    else
        empty
    end
' "$MOST_RECENT_FILE" | sed '/<bash-input>/,/<\/bash-stderr>/d; /<command-name>/,/<command-args><\/command-args>/d; /^Caveat:/d; /^<local-command-/d; /^<system-reminder>/d' > "$TMPFILE"

echo "$TMPFILE"
