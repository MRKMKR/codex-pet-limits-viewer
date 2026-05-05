# Security

## Reporting Issues

Open a GitHub issue if you find a security or privacy problem in this helper.

## Data Handling

This project must never commit local Codex runtime data, including:

- `~/.codex/auth.json`
- `~/.codex/logs_2.sqlite`
- `~/.codex/.codex-global-state.json`
- screenshots or logs containing access tokens

The helper reads those files locally at runtime only. It does not copy them into the repository or installed application directory.

## Network Access

The helper makes a read-only request to:

```text
https://chatgpt.com/backend-api/wham/usage
```

This endpoint is not a public stable API. Users should treat this project as experimental.
