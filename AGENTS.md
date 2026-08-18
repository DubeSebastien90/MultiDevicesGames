# Agent Instructions

- Do not read, print, cat, grep, parse, or otherwise inspect secret-bearing
  files such as `.env`, `.env.*`, `env/*.json`, `*.p8`, private keys, service
  account files, or local credential/config files unless the user explicitly
  asks for that exact file to be inspected.
- Prefer reading checked-in examples such as `.env.example` or
  `env/*.example.json` when environment variable names or shapes are needed.
- If a task requires knowing whether a secret file exists, ask the user or
  inspect only committed examples and documentation; do not list secret
  directories just to discover credentials.
