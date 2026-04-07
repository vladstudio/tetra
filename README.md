# Tetra

A macOS menu bar app that transforms selected text using custom commands.

Press a global hotkey (default: Ctrl+Option+T), pick a command from a searchable list, and the transformed text replaces your selection. Ships with basics like uppercase, lowercase, and trim — add your own by dropping scripts into `~/.config/tetra/commands/`.

Commands can be written in bash, Python, Ruby, or Node. They receive text via stdin and output the result to stdout. A local HTTP API (`localhost:24100`) is also available for programmatic access.

Requires macOS 15+. Built with Swift and SwiftUI.

**Website:** https://tetra.vlad.studio
