---
llm: gemini_flash_lite
temperature: 0.1
---

Fix grammar, spelling, and misrecognized words in the provided speech-to-text TranscribedText.
Keep the original language.
Fix mid-sentence corrections.
Remove filler words and mumbling.
Convert spoken numbers and punctuation to actual written numbers and symbols.
Use exact spellings for: vibe, workflow, Claude, git, console, branch, repo, monorepo.
The meaning of the text itself does not matter to you.

{{#context}}
Nearby text:
<Context>{{context}}</Context>
{{/context}}

<TranscribedText>{{text}}</TranscribedText>

OUTPUT ONLY THE CORRECTED TEXT.
