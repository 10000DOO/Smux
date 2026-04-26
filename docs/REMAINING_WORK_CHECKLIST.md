# Smux Remaining Work Checklist

Last updated: 2026-04-26

## Purpose

이 문서는 `PRD.md`, `docs/ARCHITECTURE.md`, `design_ai_agent_notifications.md`
기준으로 남은 작업을 현재 `develop` 브랜치 구현 상태에 맞춰 정리한다.

## Current Implemented Baseline

- Workspace open/close/switch, recent workspace persistence, Git branch 표시가 구현됨.
- Split panel tree, panel focus, surface descriptor, panel snapshot 저장/복원이 구현됨.
- Split panel divider drag, ratio update, nested split ratio 보존과 snapshot ratio 복원이 구현됨.
- File tree core/UI, Markdown/Mermaid 파일 강조, lazy expand, 문서 open flow가 구현됨.
- 실제 PTY terminal session 생성, 출력 buffer, 기본 ANSI 처리, copy/paste/key input,
  resize, terminate/failure state가 구현됨.
- Markdown/Mermaid editor, autosave core, conflict/failure save state, explicit save UI가 구현됨.
- 열린 문서 file watching, 외부 변경 감지, dirty conflict 보존, clean reload와 preview refresh가 구현됨.
- Markdown preview pipeline, editor-preview sync, heading anchors, internal anchor policy가 구현됨.
- 공식 Mermaid `mermaid.min.js` 번들 기반 offline WebView rendering 연결, 대표 fixture 검증,
  WebView-level offline SVG render 검증이 구현됨.
- Notification read model, routing policy, macOS notification adapter, terminal output 기반
  agent 상태 감지와 panel badge/activation 일부가 구현됨.
- 현재 slice에서 `xcodebuild -project Smux.xcodeproj -scheme Smux -destination 'platform=macOS' test`
  및 `build`가 통과함.

## Continuation Rules

- 반복 순서: 추가 기능 설계 -> 구현 -> 테스트 -> 코드리뷰 -> 리뷰 사항 수정 -> 커밋 -> 푸시.
- 큰 기능은 작은 feature slice로 자른다. 같은 slice 안에서는 설계와 구현 범위를 먼저 고정한다.
- 기존 architecture 경계 우선: `UI -> Workspace/Panel -> Feature -> Infrastructure`.
- View는 PTY/file I/O/file watcher/WebView resource loading을 직접 소유하지 않는다.
- `AgentState`는 감지와 상태 정규화만 담당하고, 표시 정책과 acknowledge는 `Notifications`에 둔다.
- 변경 후 가능한 범위에서 focused test, `xcodebuild ... test`, `xcodebuild ... build`를 실행한다.
- 코드리뷰는 findings 우선으로 수행하고, 수정 사항은 같은 slice 안에서 반영한다.

## Priority Summary

| Priority | Work | Current status |
| --- | --- | --- |
| P0-1 | 외부 파일 변경 감지와 editor/preview 반영 | Implemented and verified |
| P0-2 | panel splitter size 조절 및 ratio 복원 | Implemented and verified |
| P0-3 | terminal 호환성 고도화 | Implemented and verified |
| P0-4 | Mermaid sample fixture와 offline render 검증 | Implemented and verified |
| P0-5 | performance/memory measurement | Implemented and verified |
| P1-1 | editor Markdown syntax highlight | Implemented and verified |
| P1-2 | preview code syntax highlight | Language metadata exists, highlighter missing |
| P1-3 | keyboard actions for new editor/preview panels | Terminal/split/focus shortcuts done, editor/preview shortcuts missing |
| P1-4 | vertical tab status/last notification polish | Basic rail/badges done, richer status missing |
| P1-5 | cmux/hook parity for agent detection | Terminal output detection done, hook adapter missing |
| P1-6 | Mermaid zoom/pan controls | Preview zoom model exists, diagram pan UI missing |
| P2-1 | external link opening policy UI | Policy hard-blocks external links now |
| P2-2 | terminal theme/font settings | Basic system mono style only |
| Future | notarization/release automation/open-source prep | Deferred by PRD |

## P0 Checklist

### P0-1. External File Change Detection

- [x] Observe open document files through `FileWatching`.
- [x] Distinguish self-save updates from external disk changes.
- [x] Mark loaded document sessions as externally changed/deleted/renamed when relevant.
- [x] Show user-visible popup/banner when an open document changes externally.
- [x] Trigger preview refresh when disk changes are accepted/reloaded.
- [x] Add tests for modified, deleted, renamed, atomic replace, dirty reload guard, and self-save suppression.
- [x] Reattach file watchers after save/reload paths that can replace the underlying file descriptor.
- [x] Reprocess external file events that arrive while a save is in flight, including failed-save paths.
- [x] Reject saves when the disk fingerprint changed before coordinated write.
- [x] Stop document watchers and clear preview text snapshots on workspace switch/close lifecycle paths.

Suggested write set:

- `Smux/Editor/*`
- `Smux/Infrastructure/FileWatching/*`
- `Smux/UI/SplitPanels/SplitPanelView.swift`
- `Smux/ContentView.swift` or composition root wiring
- `SmuxTests/Editor*`, `SmuxTests/FileWatching*`

### P0-2. Panel Splitter Size And Restore

- [x] Replace fixed `HStack`/`VStack` split rendering with draggable splitter handles.
- [x] Update `PanelNode.ratio` on drag.
- [x] Persist and restore ratios through workspace snapshots.
- [x] Add tests for ratio clamping and snapshot round trip.
- [x] Verify nested split behavior.

Suggested write set:

- `Smux/Panel/*`
- `Smux/UI/SplitPanels/*`
- `Smux/Persistence/WorkspaceSnapshot.swift`
- `SmuxTests/WorkspacePanelFoundationTests.swift`, `SmuxTests/WorkspaceShellTests.swift`

### P0-3. Terminal Compatibility

- [x] Add ANSI color/style attributed rendering or adopt a terminal renderer engine.
- [x] Support common alternate screen buffer behavior through `?1049h/l`.
- [x] Improve cursor movement overwrite and clear line/screen region behavior.
- [x] Improve wide character cell-width handling.
- [x] Validate IME input path.
- [x] Add focused terminal fixture tests for cursor, clear, and alternate screen behavior.

Suggested write set:

- `Smux/Terminal/*`
- optional `Smux/Infrastructure/PTY/*`
- `SmuxTests/Terminal*`

### P0-4. Mermaid Samples And Render Verification

- [x] Add fixture Markdown containing representative Mermaid diagram types.
- [x] Add preview HTML assertions for bundled offline Mermaid script path.
- [x] Add UI or WebView-level verification that common diagrams render without network.
- [x] Document supported/unsupported Mermaid behaviors.

Suggested write set:

- `Smux/Preview/*`
- `SmuxTests/MarkdownPreview*`, `SmuxTests/PreviewWebView*`, `SmuxTests/Fixtures/*`

### P0-5. Performance And Memory Baseline

- [x] Add repeatable preview render timing test for large Markdown/Mermaid documents.
- [x] Add terminal output append/scrollback stress test.
- [x] Record initial memory/latency baseline in docs.
- [x] Identify high-cost loops and unnecessary duplicate render paths.

Suggested write set:

- `SmuxTests/*Performance*`
- `docs/PERFORMANCE_BASELINE.md`

## P1 Checklist

- [x] Editor Markdown syntax highlight in `MarkdownEditorRepresentable`.
- [ ] Preview code block syntax highlighting without network dependency.
- [ ] Keyboard action to open a new editor panel for selected Markdown/Mermaid file.
- [ ] Keyboard action to open a new preview panel for selected Markdown/Mermaid file.
- [ ] Richer left rail status for agent waiting/completed/failed and latest notification.
- [ ] Agent hook adapter for Codex/Claude-like structured events.
- [ ] Mermaid zoom/pan controls and persisted preview zoom state.

## P2 Checklist

- [ ] User-controllable external link open policy.
- [ ] Terminal font/theme settings.
- [ ] Most recent notification keyboard action.
- [ ] Release/notarization automation after feature completion.

## Parallelization Plan

The next work should run in slices. Parallel work is allowed only when write sets do not overlap.

### Current Best Sequence

1. P0-2 panel splitter ratio UI.
2. P0-3 terminal compatibility improvements.
3. P0-5 performance baseline.
4. P1 editor/preview keyboard actions.
5. P1 syntax highlighting.

### Safe Parallel Groups

| Group | Work | Owns | Avoids |
| --- | --- | --- | --- |
| A | Terminal compatibility | `Smux/Terminal/*`, `SmuxTests/Terminal*` | UI composition, Preview, Editor |
| B | Mermaid fixtures | `Smux/Preview/*`, preview tests/fixtures | Terminal, Editor, Panel |
| C | Panel splitter | `Smux/Panel/*`, `Smux/UI/SplitPanels/*` | Terminal, Preview renderer |
| D | Performance docs/tests | `docs/PERFORMANCE_BASELINE.md`, performance tests | Feature implementation files unless needed |

Panel splitter work still overlaps with `SplitPanelView`, so do not run it in parallel with
editor/preview UI changes.

## Done Checklist

- [x] Workspace open/close/switch.
- [x] Recent workspace persistence.
- [x] Git branch provider.
- [x] Split panel tree and focus navigation.
- [x] Panel surface rendering for terminal/editor/preview.
- [x] Real file tree and Markdown/Mermaid file highlighting.
- [x] Document open flow from file tree.
- [x] PTY terminal session lifecycle.
- [x] Terminal display buffer and basic ANSI cleanup.
- [x] Terminal ANSI color/style attributed rendering.
- [x] Terminal alternate screen, cursor overwrite, and clear region fixture coverage.
- [x] Terminal wide character display-cell cursor handling.
- [x] Terminal key input and paste handling.
- [x] Terminal IME committed/marked text input path.
- [x] Markdown/Mermaid editor panel.
- [x] Autosave core and explicit save UI.
- [x] Save conflict/failure state model.
- [x] Open document file watching and external change conflict/reload handling.
- [x] Atomic replace watcher restart and save/external-change race handling.
- [x] Workspace switch/close watcher and document text snapshot cleanup.
- [x] Markdown preview pipeline.
- [x] Heading anchors and internal anchor navigation policy.
- [x] Offline bundled official Mermaid renderer resource.
- [x] Representative Mermaid fixture and offline preview HTML assertions.
- [x] WebView-level offline Mermaid SVG render verification.
- [x] Performance baseline tests and measurement documentation.
- [x] Editor Markdown syntax highlighting.
- [x] Terminal-output based agent status detection and notification badges.
