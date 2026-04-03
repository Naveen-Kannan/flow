# flow

Minimal hold-to-talk dictation for `hotkey`.

The motivation is the same as the rest of the stack: explicit control flow, low idle
overhead, small diffs, and native macOS integration.

## Scope

This repo keeps the first useful split:

1. hold-to-record audio capture
2. transcription of the saved file
3. injection of the transcript at the current cursor

Those pieces stay separate so recording can be made reliable before any heavier model
or streaming work is introduced.

## Package shape

- `FlowController` owns the simple `begin`, `commit`, and `cancel` flow
- `AudioRecorder` uses native `AVAudioRecorder` and writes a temp `.m4a`
- `AudioTranscriber` is a small interface for post-record transcription
- `FlowCommands` exports command names for `hotkey` and injects the transcript back at the cursor

## CLI

```sh
swift run flowctl doctor
swift run flowctl record 3
swift run flowctl ptt
swift run flowctl transcribe /tmp/file.m4a
```

By default, `flow` looks for:

- `/opt/homebrew/bin/whisper-cli`
- `~/.local/share/flow/models/ggml-tiny.en.bin`

`FLOW_WHISPER_MODEL` and `FLOW_WHISPER_CLI` can still override those paths. Without a
usable backend, transcription falls back to a noop placeholder so the recording path
stays buildable and testable.

## Planned integration

`hotkey` imports this package and can bind:

- `flow.begin`
- `flow.commit`
- `flow.cancel`

Typical binding:

```json
{
  "bindings": [
    { "trigger": "ctrl+d", "on_press": "flow.begin", "on_release": "flow.commit" }
  ]
}
```

That remains a small startup-only diff, matching how `tiler` and `launcher` plug in.
