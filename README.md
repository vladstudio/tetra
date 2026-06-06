# Tetra

<img src="tetra-1024.png" width="128" alt="App icon">

Tetra is a small macOS menu bar app that transforms selected text. Fix typos, change case, summarize, translate, write commit messages — anything you can describe.

Select some text in any app, open Tetra from the menu bar, pick a command, and the result replaces your selection.

Requires macOS 15 or newer. A native Swift and SwiftUI app.

## Install

Paste this into Terminal:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vladstudio/tetra/main/install.sh)"
```

## How it works

Tetra lives in your menu bar. When you call it up:

1. It copies the text you currently have selected in whatever app you're using.
2. You pick a command from a searchable list.
3. Tetra runs the command and replaces your selection with the result.

Commands live in `~/.config/tetra/commands/`. You add the ones you want — they're either small shell scripts or AI prompt files. Tetra also exposes an HTTP API if you'd like to drive it from other apps or scripts.

## Commands

A command is a tiny recipe: it takes text in and gives text back. Tetra ships with none by default — you pick the ones you need.

Drop files into `~/.config/tetra/commands/`. The filename becomes the command name. The file extension is stripped, so `Uppercase.sh` shows up as **Uppercase**, and `Fix With AI.prompt.md` shows up as **Fix With AI**.

Need inspiration? The repo ships a [folder of ready-to-use examples](commands-examples/) — case conversions, wrapping, escaping, AI-powered translation and grammar fixes, and more. Copy any of them into your `commands/` folder and tweak as you like.

### Shell scripts

Any executable language works: bash, Python, Ruby, JavaScript, and so on. Files ending in `.sh`, `.py`, `.rb`, or `.js` get a sensible default interpreter, so you don't need a shebang line. The script reads the original text from standard input and prints the transformed text to standard output.

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

### AI prompts

For anything trickier than simple text manipulation, write a `.prompt.md` file. Tetra sends the prompt to a language model (which you configure — see below) and replaces your selection with the model's reply.

Inside the prompt, `{{text}}` is replaced with the selected text. You can also reference extra values passed in through the API as `{{name}}` placeholders (see the HTTP API section below).

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

## Connecting a language model

AI prompt commands need a model to talk to. Tetra speaks the OpenAI API format, so anything compatible works — OpenAI itself, Groq, OpenRouter, local Ollama, LM Studio, and so on.

Open `~/.config/tetra/config.json` and list the models you want to use under `llms`. Each one needs a name (you choose it), a base URL, and a model identifier. Add an `apiKey` if your provider requires one.

```json
{
  "server": { "port": 73784 },
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

Only list the models you'll actually use. Local servers such as Ollama or LM Studio usually don't need an API key.

Prompt files refer to these models by the name you picked (see the `llm: groq-llama` line in the examples above).

## HTTP API

Tetra runs a small local server at `http://localhost:73784`. You can call it from Shortcuts, other scripts, webhooks — anything on your machine.

**List available commands:**
```bash
curl http://localhost:73784/commands
# ["Fix With AI", "Lowercase", "Trim", "Uppercase"]
```

**Run a command on some text:**
```bash
curl -X POST http://localhost:73784/transform \
  -H "Content-Type: application/json" \
  -d '{"command": "Uppercase", "text": "hello"}'
# {"result": "HELLO"}
```

**Pass extra values into a prompt command** (these become `{{name}}` placeholders in the prompt):
```bash
curl -X POST http://localhost:73784/transform \
  -H "Content-Type: application/json" \
  -d '{"command": "Fix With AI", "text": "helo wrld", "args": {"context": "Dear colleague"}}'
```
