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
- `AudioRecorder` uses native `AVAudioRecorder` and writes a 16 kHz mono PCM `.wav`
- `AudioTranscriber` is a small interface for post-record transcription
- `FlowCommands` exports command names for `hotkey` and injects the transcript back at the cursor

## CLI

```sh
swift run flowctl doctor
swift run flowctl prepare
swift run flowctl record 3
swift run flowctl ptt
swift run flowctl transcribe /tmp/file.wav
```

The default backend is **Parakeet TDT 0.6B v2**, the English model, through
FluidAudio/Core ML. `hkd` preloads it on startup and retains it between recordings;
transcription jobs are serialized because the decoder has mutable state. Audio stays
local. First setup downloads roughly 450 MB of model assets to
`~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2-coreml`.
`FLOW_PARAKEET_MODEL_DIR` overrides the model cache root. Startup/load failures are
logged, and a later transcription retries initialization.

macOS 14 or later is required. FluidAudio 0.12.4 and swift-transformers 1.1.6 are
pinned to support this Mac's Swift 6.1 toolchain. Capturing PCM directly avoids AAC
finalization and the extra conversion subprocess.

Set `FLOW_TRANSCRIBER=whisper` to use the previous backend. It looks for
`/opt/homebrew/bin/whisper-cli` and `~/.local/share/flow/models/ggml-tiny.en.bin`;
`FLOW_WHISPER_MODEL` and `FLOW_WHISPER_CLI` override those paths. Both backends report failures instead of inserting placeholder text. Explicit Whisper
path overrides are honored; invalid overrides fail instead of silently choosing a fallback.
Whisper stdout and stderr are drained while it runs, including verbose failures.

`flowctl benchmark <audio-file>` prints model preparation time and three sequential
transcription timings. This is a diagnostic, not a voice-quality evaluation.

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

## Tunes during dictation

Control+D pauses Tunes before opening the microphone. Playback resumes 4.5 seconds
after recording stops, including cancellation and recorder failures. The delay lets
macOS finish releasing the input device and restore normal output audio before music
returns. A new recording during this cooldown cancels the pending resume and retains
the pause lease. Already paused music stays paused. `FLOW_TUNES_RESUME_DELAY` can set
the cooldown in seconds (0–10; default 4.5). Transcription starts immediately after the
recorder stops, independently of the music cooldown. Tunes is controlled through its localhost API, without activating its
window or synthesizing another keyboard shortcut. Missing/unresponsive Tunes does not
prevent dictation; the request is bounded to one second.

`FlowCommands` serializes recording commands on a background queue so the keyboard event
tap stays responsive and a quick release is handled after its press. Recording and
transcription errors are logged through `com.nkannan.flow` instead of silently ignored.

Tunes must include the `/control/dictation/begin` and `/control/dictation/end` endpoints.
Rebuild and restart whichever app has changed. `flowctl record` and `ptt` wait for
the delayed music restoration before exiting. A recording
lease is renewed every minute and expires after ten minutes if the dictation process
disappears. Manual playback or track changes override
automatic restoration.
