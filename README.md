# Tetra

<img src="tetra.png" width="128" alt="App icon">

A macOS menu bar app that transforms selected text using custom commands.

Pick a command from a searchable list, and the transformed text replaces your selection. Drop commands into `~/.config/tetra/commands/`.

Commands can be simple scripts that receive text via stdin and output the result to stdout, or `.prompt.md` files that Tetra runs through a configured OpenAI-compatible LLM. A local HTTP API (`localhost:24100`) is also available for programmatic access.

Requires macOS 15+. Built with Swift and SwiftUI.

**Website:** https://apps.vlad.studio/tetra

## API

Tetra runs an HTTP server on `localhost:24100` for programmatic access.

**`GET /commands`** — list available commands:
```bash
curl http://localhost:24100/commands
# ["Fix With AI", "Lowercase", "Trim", "Uppercase"]
```

**`POST /transform`** — run a command on text:
```bash
curl -X POST http://localhost:24100/transform \
  -H "Content-Type: application/json" \
  -d '{"command": "Uppercase", "text": "hello"}'
# {"result": "HELLO"}
```

An optional `args` object passes named values to `.prompt.md` commands:
```bash
curl -X POST http://localhost:24100/transform \
  -H "Content-Type: application/json" \
  -d '{"command": "Fix With AI", "text": "helo wrld", "args": {"context": "Dear colleague"}}'
```

## Configuration

Edit `~/.config/tetra/config.json`. The `llms` object defines named OpenAI-compatible model configurations. Prompt commands reference one of these names in frontmatter.

```json
{
  "server": { "port": 24100 },
  "llms": {
    "local-gemma": {
      "baseUrl": "http://localhost:11434/v1",
      "model": "gemma3:4b"
    },
    "groq-llama": {
      "baseUrl": "https://api.groq.com/openai/v1",
      "apiKey": "gsk_...",
      "model": "llama-3.3-70b-versatile"
    }
  }
}
```

Only include the LLMs you use. Local Ollama-compatible endpoints usually do not need an API key.

## Commands

Drop scripts or prompt files into `~/.config/tetra/commands/`. For scripts, the filename minus extension becomes the command name. For prompt commands, `.prompt.md` is removed from the filename.

### Local Scripts

Scripts receive text via stdin and output the transformed text to stdout. Any executable language works; `.sh`, `.py`, `.rb`, and `.js` get a default interpreter.

`Uppercase.sh`:
```bash
#!/bin/bash
tr '[:lower:]' '[:upper:]'
```

`Trim.sh`:
```bash
#!/bin/bash
sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
```

### Prompt Commands

Prompt commands are `.prompt.md` files. Tetra renders `{{text}}` and any values from the API `args` object, then sends the prompt to the configured LLM.

`Fix With AI.prompt.md`:
```text
---
llm: groq-llama
temperature: 0.3
---

Fix grammar, spelling, and misrecognized words in the provided speech-to-text transcription.
Keep the original language.
Remove filler words and mumbling.

{{#context}}
Context:
{{context}}
{{/context}}

Text:
{{text}}

OUTPUT ONLY THE CORRECTED TEXT.
```

`Commit message.prompt.md`:
```text
---
llm: groq-gpt-oss
temperature: 0.3
---

Write a concise, human-friendly, meaningful git commit message for this diff.
Imperative mood, single line, under 80 characters.
No quotes around the message.

Diff:
{{text}}

OUTPUT ONLY THE COMMIT MESSAGE.
```
