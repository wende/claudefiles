# claudefiles

A collection of utility scripts for Claude Code workflows.

## Scripts

### extract-discussion.sh

Extracts the most recent Claude Code discussion and formats it as a readable conversation. Automatically filters out tool calls (Bash, Grep, Glob, etc.) and tool results to show only the meaningful dialog.

**Usage:**
```bash
./extract-discussion.sh          # Extract without thinking blocks
./extract-discussion.sh --thinking  # Include thinking blocks with [THINKING] markers
```

**Example output:**
```
USER:
Can you explain how the auth works?

ASSISTANT:
The authentication system uses JWT tokens stored in localStorage. When a user logs in, the server validates credentials and returns a signed token. This token is then included in the Authorization header for subsequent requests.

USER:
How are tokens refreshed?

ASSISTANT:
Tokens are refreshed automatically when they expire. The API client intercepts 401 responses and uses a refresh token to obtain a new access token without requiring the user to log in again.
```

### statusline-command.sh

A Claude Code custom status line command that displays real-time workspace information. Shows current directory, git status, active model, and token usage with model-specific weighting.

**Setup:**
Configure in Claude Code settings as a custom status line command.

**Example output:**
```
➜  ~/projects/awesome-claude git:(main) [Haiku] 1.2M/60% (O:0 S:0 H:1.2M)
```

**Components:**
- `➜` - Ready indicator
- `~/projects/awesome-claude` - Current directory
- `git:(main)` - Current branch (with `✗` indicator if uncommitted changes)
- `[Haiku]` - Active Claude model
- `1.2M/60%` - Token usage in current 3-hour window vs limit
- `(O:X S:X H:X)` - Breakdown by model: Opus, Sonnet, Haiku with weighted tokens

**Token Weighting:**
- Haiku: 1x input, 5x output
- Sonnet: 3x input, 15x output
- Opus: 15x input, 75x output

Token usage resets every 3 hours at: 00:00, 03:00, 06:00, 09:00, 12:00, 15:00, 18:00, 21:00 UTC
