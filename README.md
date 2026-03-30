# flow

Minimal dictation groundwork for `hotkey`.

The motivation is the same as the rest of the stack: explicit control flow, low idle
overhead, small diffs, and native macOS integration.

## Scope

This repo starts with the lightest useful split:

1. hold-to-record audio capture
2. transcription of the saved file

Those pieces stay separate so recording can be made reliable before any heavier model
or streaming work is introduced.

## Package shape

- `FlowController` owns the simple `begin`, `commit`, and `cancel` flow
- `AudioRecorder` uses native `AVAudioRecorder` and writes a temp `.m4a`
- `AudioTranscriber` is a small interface for post-record transcription
- `FlowCommands` exports future-facing command names for `hotkey`

## CLI

```sh
swift run flowctl doctor
swift run flowctl record 3
swift run flowctl ptt
swift run flowctl transcribe /tmp/file.m4a
```

`FLOW_WHISPER_MODEL` and `FLOW_WHISPER_CLI` can be set to try a local `whisper.cpp`
binary. Without that, transcription falls back to a noop placeholder so the recording
path stays buildable and testable.

## Planned integration

Later, `hotkey` can add this package as a dependency and bind:

- `flow.begin`
- `flow.commit`
- `flow.cancel`

That should stay a small startup-only diff, matching how `tiler` and `launcher` plug in.
