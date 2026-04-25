# Smux Remaining Work Checklist

Last updated: 2026-04-25

## Purpose

이 문서는 `PRD.md`, `docs/ARCHITECTURE.md`, `design_ai_agent_notifications.md` 기준으로 현재 남은 미구현 기능을 우선순위별로 정리한 작업 체크리스트다.

현재 구현 상태는 다음 수준이다.

- 작업 공간 열기와 기본 shell은 부분 구현됨.
- 패널 모델, 분할 tree, placeholder surface는 구현됨.
- workspace snapshot 저장/복원 일부와 in-memory recent workspace는 구현됨.
- notification read model, routing policy, macOS UserNotifications adapter는 구현됨.
- 터미널 실행, 파일 트리, editor, Markdown preview, Mermaid renderer, agent 상태 감지는 실제 기능이 아직 없다.

## Continuation Rules

- 큰 기능은 한 번에 모두 구현하지 않는다. 아래 순서대로 하나의 feature slice씩 진행한다.
- 각 feature slice는 DEV 단계에서 3가지 옵션과 파일별 수정 계획을 먼저 제시하고 사용자 승인을 받은 뒤 구현한다.
- 기존 architecture 경계를 우선한다: `UI -> Workspace/Panel -> Feature -> Infrastructure`.
- View가 infrastructure를 직접 호출하지 않게 한다.
- `AgentState`는 감지만 담당하고, 표시 정책과 acknowledge는 `Notifications`에 둔다.
- 변경 후 가능한 범위에서 `xcodebuild -project Smux.xcodeproj -scheme Smux -destination platform=macOS ... build/test`를 실행한다.

## Priority Summary

| Priority | Goal | Status |
| --- | --- | --- |
| P0-1 | 실제 파일 트리 | Not started |
| P0-2 | 실제 터미널 실행 | Not started |
| P0-3 | panel surface 실제 view 연결 | Not started |
| P0-4 | Markdown/Mermaid editor | Not started |
| P0-5 | autosave와 conflict detection | Not started |
| P0-6 | Markdown preview pipeline | Not started |
| P0-7 | offline Mermaid renderer | Not started |
| P0-8 | editor-preview sync | Not started |
| P0-9 | file watching | Not started |
| P0-10 | terminal output 기반 agent 상태 감지와 알림 연결 | Partially started |
| P1 | keyboard, badge, search, syntax highlight, performance prep | Not started |
| P2 | recent workspace persistence, polish, distribution prep | Not started |

## Parallel Agent Work Groups

이 섹션은 여러 에이전트에게 동시에 맡기기 위한 묶음이다. 병렬 작업은 서로 같은 파일을 수정하지 않는 것을 원칙으로 한다. `WorkspaceShellView`, `ContentView`, `SplitPanelView`, `LeftRailView`, `WorkspaceCoordinator`, `AppCommandRouter`처럼 composition과 UI integration 파일은 충돌 가능성이 높으므로 한 명의 integration owner가 마지막에 합치는 방식으로 진행한다.

### Parallelization Rules

- Core/domain 작업과 UI/DI integration 작업을 분리한다.
- 병렬 에이전트는 자기 write set 밖의 파일을 수정하지 않는다.
- 공유 contract가 필요하면 먼저 작은 contract-only PR/commit을 만든 뒤 병렬 작업을 시작한다.
- 같은 feature 안에서도 infrastructure, domain, UI를 동시에 건드리면 충돌이 커지므로 한 agent가 하나의 bounded context를 소유한다.
- 병렬 작업 결과는 build 가능한 작은 단위로 합친다. 합친 뒤 integration owner가 전체 build/test를 실행한다.

### Dependency Map

```text
Workspace/Panel foundation
  -> FileTree core
      -> FileTree UI integration
          -> Document open flow

Workspace/Panel foundation
  -> Terminal core
      -> Terminal panel integration
          -> Agent output stream integration

Document core
  -> Editor UI
  -> Autosave/conflict
  -> Preview sync

Markdown preview core
  -> Mermaid renderer core
      -> Preview panel integration

Notification core
  -> AgentState transition store
      -> Terminal output integration
      -> Panel badge / activation integration
```

### Wave 0. Contract Freeze

한 agent 또는 main thread에서 먼저 끝내야 하는 준비 작업이다. 이 단계가 끝나면 아래 Wave 1을 병렬로 진행할 수 있다.

- [ ] Terminal renderer strategy 결정: existing engine embed 또는 minimal renderer.
- [ ] Markdown renderer strategy 결정: Swift-native parser 또는 WebView/unified HTML pipeline.
- [ ] File access policy 결정: sandbox off MVP 또는 sandbox on + security-scoped bookmark.
- [ ] 공통 file-system helper 소유권 결정: `FileTree` agent가 소유할지 `Editor` agent가 소유할지 정한다.
- [ ] Shared contracts만 먼저 추가할지 결정: `DocumentSessionStore`, `TerminalOutputSink`, `FileTreeLoading`, `PreviewRendering` 같은 protocol.

### Wave 1. Core Work That Can Run In Parallel

| Agent | Work group | Owns write set | Must not touch | Depends on |
| --- | --- | --- | --- | --- |
| A | File Tree Core | `Smux/FileTree/*`, `SmuxTests/FileTree*` | `LeftRailView`, `WorkspaceShellView`, `WorkspaceCoordinator` | File access policy |
| B | Terminal Core | `Smux/Terminal/*`, `Smux/Infrastructure/PTY/*`, `SmuxTests/Terminal*` | `SplitPanelView`, `WorkspaceShellView`, `ContentView` | Terminal strategy |
| C | Document/Edit Core | `Smux/Editor/*`, `SmuxTests/Editor*` | `Preview/*`, `LeftRailView`, `WorkspaceCoordinator` | File access policy |
| D | Markdown Preview Core | `Smux/Preview/MarkdownPreviewPipeline.swift`, Markdown render helper files, `SmuxTests/MarkdownPreview*` | `MermaidRenderCoordinator.swift`, UI WebView files | Markdown strategy |
| E | Mermaid Renderer Core | `Smux/Preview/MermaidRenderCoordinator.swift`, Mermaid resource files, `SmuxTests/Mermaid*` | `MarkdownPreviewPipeline.swift`, preview UI files | Mermaid bundle approach |
| F | Agent State Core | `Smux/AgentState/*`, `SmuxTests/AgentState*` | `Terminal/*`, `Notifications/*`, UI files | Notification model already exists |

Wave 1 acceptance:

- [ ] Each agent adds or updates focused tests for its own write set.
- [ ] No agent changes composition root or shared UI integration files.
- [ ] Each group can compile independently or has clearly documented temporary compile gate.
- [ ] The integration owner reviews public/internal protocol shape before merge.

### Wave 2. Integration Work That Should Be Mostly Sequential

이 단계는 같은 파일을 여러 기능이 동시에 수정할 가능성이 높으므로 병렬 작업으로 나누지 않는다.

| Order | Integration slice | Files likely touched | Depends on |
| --- | --- | --- | --- |
| 1 | File tree UI integration | `LeftRailView`, `WorkspaceShellView`, `ContentView` or composition | Agent A |
| 2 | Panel surface renderer | `SplitPanelView`, `PanelSurfacePlaceholderView`, new surface renderer, composition | Agents B, C, D |
| 3 | Document open flow | `WorkspaceCoordinator`, `AppCommandRouter`, document session store | Agents A, C |
| 4 | Editor-preview sync | `WorkspaceCoordinator`, editor store, preview store, panel surface renderer | Agents C, D, E |
| 5 | Terminal output to AgentState | terminal controller/view model, `AgentStateStore` wiring | Agents B, F |
| 6 | Notification UI activation and badges | `WorkspaceShellView`, `SplitPanelView`, `LeftRailView`, `ContentView` | Agent F and existing notification core |
| 7 | Persistence completion | `WorkspaceSnapshot`, `WorkspaceRepository`, coordinator | terminal/editor/preview session stores |

Wave 2 acceptance:

- [ ] App launches with real file tree and no placeholder-only left rail.
- [ ] Terminal/editor/preview panel descriptors render real views.
- [ ] Workspace open, split, focus, document open, and notification UI still work together.
- [ ] `xcodebuild ... build` passes.
- [ ] `xcodebuild ... test` passes or failures are documented with root cause.

### Wave 3. P1 Parallel Work After MVP Surfaces Exist

| Agent | Work group | Owns write set | Depends on |
| --- | --- | --- | --- |
| G | Keyboard commands | `Smux/App/*`, command routing tests | Real panel/document/terminal commands |
| H | Editor enhancements | `Smux/Editor/*`, editor tests | Editor MVP |
| I | Preview enhancements | `Smux/Preview/*`, preview tests | Markdown/Mermaid MVP |
| J | Workspace/session metadata | `Smux/Workspace/*`, `Smux/Persistence/*`, git service files | Session stores |
| K | Performance measurement | benchmark docs/tests, fixtures | MVP surfaces |

### Recommended Parallel Start

다음 병렬 시작 조합이 가장 충돌이 적다.

- [ ] Agent A: `File Tree Core`
- [ ] Agent B: `Terminal Core`
- [ ] Agent C: `Document/Edit Core`
- [ ] Agent D: `Markdown Preview Core`
- [ ] Agent F: `Agent State Core`

Agent E, `Mermaid Renderer Core`, 는 Mermaid bundle 방식과 Markdown pipeline의 Mermaid block contract가 정해진 뒤 시작하는 편이 안전하다.

### Exact 4-Agent Assignment

아래 4개로 나눠서 시작한다. 지금 단계에서는 UI/DI 통합 파일을 동시에 건드리지 않는 것이 핵심이다. 따라서 각 에이전트는 core 구현과 테스트까지만 맡고, `WorkspaceShellView`, `ContentView`, `SplitPanelView`, `LeftRailView`, `WorkspaceCoordinator`, `AppCommandRouter` 통합은 별도 integration 단계에서 처리한다.

| Agent | Primary goal | Owns write set | Must not touch |
| --- | --- | --- | --- |
| Agent 1 | File Tree Core | `Smux/FileTree/*`, `SmuxTests/FileTree*` | `Smux/UI/*`, `Smux/Workspace/WorkspaceCoordinator.swift`, `Smux/App/AppCommandRouter.swift` |
| Agent 2 | Terminal Core | `Smux/Terminal/*`, `Smux/Infrastructure/PTY/*`, `SmuxTests/Terminal*` | `Smux/UI/*`, `Smux/Workspace/*`, `Smux/AgentState/*` |
| Agent 3 | Document Editor Core | `Smux/Editor/*`, `SmuxTests/Editor*` | `Smux/Preview/*`, `Smux/UI/*`, `Smux/Workspace/WorkspaceCoordinator.swift` |
| Agent 4 | Preview and Agent-State Core | `Smux/Preview/MarkdownPreviewPipeline.swift`, new Markdown preview helper files, `Smux/AgentState/*`, `SmuxTests/MarkdownPreview*`, `SmuxTests/AgentState*` | `Smux/Terminal/*`, `Smux/Notifications/*`, `Smux/UI/*` |

Agent 4가 두 영역을 맡는 이유:

- Markdown preview core와 AgentState core는 현재 서로 직접 의존하지 않는다.
- 둘 다 UI/DI integration 전의 순수 core 작업으로 제한할 수 있다.
- 4개 에이전트 제한 안에서 Mermaid renderer는 아직 bundle 방식 결정이 필요하므로 첫 병렬 시작에서 제외하는 편이 안전하다.

#### Agent 1 Prompt: File Tree Core

```text
You are Agent 1 for Smux. Work only on File Tree Core.

Goal:
- Implement the non-UI file tree core needed for P0-1.

Allowed write set:
- Smux/FileTree/*
- SmuxTests/FileTree*

Do not edit:
- Smux/UI/*
- Smux/Workspace/WorkspaceCoordinator.swift
- Smux/App/AppCommandRouter.swift
- Smux/Panel/*

Tasks:
- Implement a narrow file tree loading abstraction if needed.
- Make FileTreeStore able to load a workspace root URL or equivalent root context.
- Implement lazy directory expansion.
- Sort directories before files, then by localized name.
- Mark .md, .markdown, .mmd, .mermaid as document candidates.
- Preserve FileTreeNode as the UI-facing value model.
- Add focused tests for document candidate classification, child sorting, root loading, and lazy expansion.

Constraints:
- Do not wire this into LeftRailView yet.
- Do not route document selection yet.
- Do not add broad architecture or unrelated refactors.

Final response:
- List changed files.
- State what remains for UI integration.
- State test/build result.
```

#### Agent 2 Prompt: Terminal Core

```text
You are Agent 2 for Smux. Work only on Terminal Core.

Goal:
- Implement the non-UI terminal core needed for P0-2.

Allowed write set:
- Smux/Terminal/*
- Smux/Infrastructure/PTY/*
- SmuxTests/Terminal*

Do not edit:
- Smux/UI/*
- Smux/Workspace/*
- Smux/AgentState/*
- Smux/Notifications/*
- Smux/ContentView.swift

Tasks:
- Add a PTY infrastructure boundary under Smux/Infrastructure/PTY.
- Implement TerminalSessionController.createSession without fatalError.
- Start a shell or explicit command in the workspace working directory.
- Track process ID, status, createdAt, lastActivityAt, title, and failure state.
- Add output stream or callback boundary, but do not connect it to AgentState yet.
- Implement terminate behavior.
- Implement TerminalViewModel sendInput and resize by delegating to terminal core APIs.
- Add focused tests for metadata, lifecycle state, failure handling, and injectable PTY behavior.

Constraints:
- Do not implement terminal panel UI rendering in SplitPanelView.
- Do not connect terminal output to AgentState.
- Keep agent classification out of Terminal.

Final response:
- List changed files.
- Explain the terminal API that integration should call.
- State test/build result.
```

#### Agent 3 Prompt: Document Editor Core

```text
You are Agent 3 for Smux. Work only on Document Editor Core.

Goal:
- Implement the non-preview document editing core needed for P0-4 and the foundation for P0-5.

Allowed write set:
- Smux/Editor/*
- SmuxTests/Editor*

Do not edit:
- Smux/Preview/*
- Smux/UI/*
- Smux/Workspace/WorkspaceCoordinator.swift
- Smux/App/AppCommandRouter.swift
- Smux/FileTree/*

Tasks:
- Add document loading and language detection for .md, .markdown, .mmd, .mermaid, and fallback plain text.
- Make DocumentEditorViewModel load a document session and update text state.
- Maintain textVersion, isDirty, saveState, fileFingerprint, and selectedRange where appropriate.
- Implement explicit saveNow with atomic write if feasible in this slice.
- Implement or scaffold AutoSaveCoordinator with debounce-friendly API, but avoid UI alerts.
- Add tests for language detection, load, updateText state transitions, save success, and save failure.

Constraints:
- Do not wire editor changes to MarkdownPreviewPipeline yet.
- Do not implement left rail or panel integration.
- Do not implement conflict UI in this slice.

Final response:
- List changed files.
- State what remains for autosave/conflict UI and preview sync.
- State test/build result.
```

#### Agent 4 Prompt: Preview and Agent-State Core

```text
You are Agent 4 for Smux. Work only on Markdown Preview Core and Agent-State Core.

Goal:
- Implement pure/core work for P0-6 and P0-10 without UI, terminal, or notification integration.

Allowed write set:
- Smux/Preview/MarkdownPreviewPipeline.swift
- New Smux/Preview/* helper files for Markdown preview only
- Smux/AgentState/*
- SmuxTests/MarkdownPreview*
- SmuxTests/AgentState*

Do not edit:
- Smux/Terminal/*
- Smux/Notifications/*
- Smux/UI/*
- Smux/ContentView.swift
- Smux/Workspace/*
- Smux/Preview/MermaidRenderCoordinator.swift unless only defining a minimal non-breaking protocol contract is unavoidable

Tasks:
- Replace MarkdownPreviewPipeline fatalError with a deterministic MVP renderer or renderer abstraction.
- Render required Markdown MVP features: headings, lists, tables, code blocks, blockquotes, links.
- Return PreviewState with sanitizedMarkdown, renderVersion, errors, and empty Mermaid block list if Mermaid is not implemented.
- Discard or model stale render results by version where appropriate.
- Convert AgentStatusDetector from always nil to high-signal pattern detection for Codex/Claude states.
- Add AgentStateStore or equivalent transition-dedupe core if it can be done without NotificationStore edits.
- Add tests for Markdown rendering features.
- Add tests for agent state detection and duplicate transition suppression.

Constraints:
- Do not bundle Mermaid yet.
- Do not connect terminal output to AgentState.
- Do not deliver notifications or edit NotificationStore.
- Do not add preview WebView UI integration.

Final response:
- List changed files.
- State which Markdown/Mermaid pieces remain.
- State how terminal integration should feed AgentState later.
- State test/build result.
```

### After The 4 Agents Finish

Integration owner should merge in this order:

- [ ] Merge Agent 1 and wire file tree UI.
- [ ] Merge Agent 3 and wire document open flow.
- [ ] Merge Agent 4 Markdown preview core and wire preview surface.
- [ ] Merge Agent 2 and wire terminal surface.
- [ ] Wire terminal output to Agent 4 AgentState core.
- [ ] Wire AgentState notifications to existing `NotificationStore`.
- [ ] Add panel badge and notification activation UI.
- [ ] Run full build/test.

## P0 Checklist

### P0-1. File Tree MVP

Requirements: `FT-1`, `FT-2`, `FT-4`, `ED-6`

Current evidence:

- `Smux/FileTree/FileTreeStore.swift` has empty `loadRoot` and `expand`.
- `Smux/UI/LeftRail/LeftRailView.swift` still renders `"File tree pending"`.

Checklist:

- [ ] Define narrow file tree loading service protocol.
- [ ] Load active workspace root as `FileTreeNode`.
- [ ] Lazy-load directory children on expand.
- [ ] Sort directories before files.
- [ ] Mark `.md`, `.markdown`, `.mmd`, `.mermaid` as document candidates.
- [ ] Render real tree in left rail instead of placeholder text.
- [ ] Highlight Markdown/Mermaid file names more strongly than other files.
- [ ] Route document selection through `DocumentOpening.openDocument(_:preferredSurface:)`.
- [ ] Add unit tests for document candidate classification, lazy expansion, and sorting.

Verification:

- [ ] Open workspace and see real root files.
- [ ] Expand nested directories.
- [ ] Select Markdown/Mermaid file and confirm panel surface changes.
- [ ] Build and test pass.

### P0-2. Terminal MVP

Requirements: `TM-1` to `TM-5`, `TM-8`, `TM-9`, `PF-1`

Current evidence:

- `Smux/Terminal/TerminalSessionController.swift` has `fatalError("TODO")`.
- `Smux/Terminal/TerminalViewModel.swift` has empty `sendInput` and `resize`.
- `Smux/Terminal/TerminalViewRepresentable.swift` returns an empty `NSView`.

Checklist:

- [ ] Decide terminal rendering strategy before implementation.
- [ ] Add PTY infrastructure boundary under `Infrastructure/PTY`.
- [ ] Create shell process in workspace root.
- [ ] Capture stdout/stderr output stream.
- [ ] Send keyboard input to PTY.
- [ ] Support resize through PTY ioctl.
- [ ] Track process lifecycle and exit status.
- [ ] Keep `TerminalSession` metadata separate from agent classification.
- [ ] Render terminal surface in panel.
- [ ] Feed terminal output chunks to future `AgentState` boundary.
- [ ] Add tests around session creation metadata and lifecycle state where feasible.

Verification:

- [ ] New terminal starts in selected workspace root.
- [ ] Basic shell commands run.
- [ ] Input, paste, resize, and process exit do not crash.
- [ ] Build and test pass.

### P0-3. Panel Surface Rendering

Requirements: `PN-2`, MVP items 3, 4, 6, 7

Current evidence:

- `PanelSurfacePlaceholderView` only swaps descriptors.
- `SplitPanelView` always renders placeholder UI for terminal/editor/preview surfaces.

Checklist:

- [ ] Introduce a feature surface renderer that maps `PanelSurfaceDescriptor` to actual views.
- [ ] Keep placeholder only for `.empty` or failed/unavailable surfaces.
- [ ] Inject feature view models from composition root or narrow factories.
- [ ] Preserve `SplitPanelView` as split tree renderer, not feature runtime owner.
- [ ] Add focused state and panel badge extension point.

Verification:

- [ ] Terminal/editor/preview descriptors render distinct real surfaces.
- [ ] Split and focus still work.
- [ ] Existing panel tests still pass.

### P0-4. Markdown/Mermaid Editor MVP

Requirements: `ED-1`, `ED-2`, `ED-4`, `ED-5`

Current evidence:

- `DocumentEditorViewModel.load`, `updateText`, `saveNow` are empty.
- `MarkdownEditorRepresentable` returns an empty `NSView`.

Checklist:

- [ ] Add document session store or coordinator for open documents.
- [ ] Load file content into `DocumentSession`.
- [ ] Detect document language from extension.
- [ ] Replace empty `NSView` with `NSTextView` bridge.
- [ ] Wire text change callbacks into `DocumentEditorViewModel`.
- [ ] Maintain `textVersion`, `isDirty`, and `saveState`.
- [ ] Provide explicit save command path.
- [ ] Keep preview invalidation independent from save completion.
- [ ] Add tests for language detection and state transitions.

Verification:

- [ ] Open `.md` and `.mmd` files from file tree.
- [ ] Edit text in panel.
- [ ] Save without losing cursor/editor state.
- [ ] Build and test pass.

### P0-5. Autosave and Conflict Detection

Requirements: `ED-3`

Current evidence:

- `AutoSaveCoordinator` methods are empty.
- `FileFingerprint` and `DocumentConflict` model exist but are not used.

Checklist:

- [ ] Implement file fingerprint read.
- [ ] Implement debounced autosave scheduling.
- [ ] Use temp file plus atomic replace for saves.
- [ ] Detect external modification before save.
- [ ] Set conflicted state when local dirty content conflicts with external changes.
- [ ] Show user-visible conflict alert or sheet.
- [ ] Provide MVP conflict actions: overwrite local, reload external, save copy.
- [ ] Emit workspace notification for save failure/conflict if useful.

Verification:

- [ ] Autosave writes changed document.
- [ ] External file change while dirty triggers conflict state.
- [ ] Save failure is visible and recoverable.

### P0-6. Markdown Preview MVP

Requirements: `MD-1`, `MD-2`, `MD-3`

Current evidence:

- `MarkdownPreviewPipeline.render` has `fatalError("TODO")`.
- `PreviewWebViewRepresentable` returns an empty `NSView`.

Checklist:

- [ ] Decide Markdown renderer strategy before implementation.
- [ ] Convert Markdown text to sanitized render artifact.
- [ ] Render headings, lists, tables, code blocks, blockquotes, and links.
- [ ] Render preview panel from editor buffer, not only saved file.
- [ ] Discard stale render results by `renderVersion`.
- [ ] Add basic error state.
- [ ] Add renderer tests for required Markdown features.

Verification:

- [ ] Editing Markdown updates preview automatically.
- [ ] Tables, code blocks, links, and headings render.
- [ ] Large document update remains responsive enough for MVP.

### P0-7. Offline Mermaid Renderer

Requirements: `MM-1`, `MM-2`, `MM-3`, `MM-5`, `MM-8`, `PF-5`

Current evidence:

- `MermaidRenderCoordinator.render` has `fatalError("TODO")`.
- No bundled Mermaid runtime asset was found in the repository.

Checklist:

- [ ] Add official Mermaid renderer as bundled local resource.
- [ ] Add WebKit rendering infrastructure behind a protocol.
- [ ] Block remote network/resource loading.
- [ ] Extract `mermaid` code blocks from Markdown.
- [ ] Render Mermaid blocks to sanitized SVG or HTML artifact.
- [ ] Surface Mermaid syntax/render errors inline with source range.
- [ ] Ensure render cancellation or stale result discard.
- [ ] Add Mermaid sample fixture Markdown file.
- [ ] Add offline renderer verification tests where feasible.

Verification:

- [ ] Mermaid code block renders without network.
- [ ] Invalid Mermaid syntax displays a useful error.
- [ ] Markdown preview still works when Mermaid block fails.

### P0-8. Editor and Preview Synchronization

Requirements: `ED-5`, `MD-3`, `MM-3`, MVP item 9

Checklist:

- [ ] Add document-to-preview pairing model.
- [ ] Send editor buffer changes to preview pipeline immediately.
- [ ] Do not wait for autosave before preview update.
- [ ] Keep preview source document ID and render version aligned.
- [ ] Restore editor/preview pairing from workspace snapshot.

Verification:

- [ ] Editor and preview show the same file.
- [ ] Split editor-preview layout survives workspace reopen.

### P0-9. File Watching

Requirements: `ED-3`, `MD-3`, `PF-5`

Checklist:

- [ ] Add file watcher infrastructure boundary.
- [ ] Watch workspace root for file tree invalidation.
- [ ] Watch opened files for external edits.
- [ ] Debounce event storms.
- [ ] Invalidate only loaded/expanded subtrees where possible.
- [ ] Integrate opened document external change path with conflict detection.

Verification:

- [ ] Creating/deleting files updates file tree.
- [ ] External edit to open document is detected.
- [ ] Large repository events do not freeze UI.

### P0-10. Agent State and Notification Integration

Requirements: `TM-6`, `NT-1` to `NT-4`, MVP item 10

Current evidence:

- `AgentStatusDetector.detectStatus` always returns `nil`.
- `NotificationStore` and macOS delivery exist, but no terminal output is connected to it.
- Panel badges and notification activation are not wired.

Checklist:

- [ ] Add `AgentStatusDetecting` protocol if not already present in implementation.
- [ ] Add `AgentStateStore` for per-session state memory and transition dedupe.
- [ ] Parse high-signal Codex/Claude output patterns.
- [ ] Add hook payload extension point.
- [ ] Emit `AgentNotification` only on meaningful transitions.
- [ ] Connect terminal output stream to `AgentStateStore`.
- [ ] Add panel badge derivation in `WorkspaceShellView`.
- [ ] Add notification select/ack callbacks in left rail.
- [ ] Add shared activation path to focus target panel.
- [ ] Wire macOS notification response to same activation path.

Verification:

- [ ] Repeated output does not spam notifications.
- [ ] Permission/completed/waiting/failure state appears in left rail.
- [ ] Panel badge points to the correct panel.
- [ ] macOS notification click focuses the related panel.

## P1 Checklist

### Keyboard and Navigation

Requirements: `PN-3`, `KB-1`, `KB-2`

- [ ] Keyboard command for new terminal.
- [ ] Keyboard command for new editor.
- [ ] Keyboard command for new preview.
- [ ] Keyboard command for split horizontal/vertical.
- [ ] Keyboard focus movement between panels.
- [ ] Keyboard action for latest notification if pulled into MVP scope.

### Workspace and Session Metadata

Requirements: `WS-3`, `WS-4`, `VT-2`, `VT-3`

- [ ] Add Git branch service behind infrastructure boundary.
- [ ] Show branch in workspace tab after opening workspace.
- [ ] Represent terminal/document/preview sessions in left rail.
- [ ] Show agent status badge in session rows.
- [ ] Persist panel sizes and active panel more completely.

### Editor Enhancements

Requirements: `ED-7`, `ED-8`

- [ ] Search.
- [ ] Undo/redo integration with `NSTextView`.
- [ ] Save shortcut.
- [ ] Markdown syntax highlighting.
- [ ] Mermaid syntax highlighting or at least fenced block visibility.

### Preview Enhancements

Requirements: `MD-4`, `MD-5`, `MM-4`, `MM-6`, `MM-7`

- [ ] Code block syntax highlighting.
- [ ] Internal anchor navigation.
- [ ] Mermaid zoom/pan.
- [ ] Wider Mermaid diagram coverage.
- [ ] Official Mermaid sample fixture coverage.

### Performance and Reliability Prep

Requirements: `PF-2`, `PF-3`, `PF-6`, `PF-7`

- [ ] Define measurable MVP thresholds in tests or manual checklist.
- [ ] Measure cold start.
- [ ] Measure terminal creation latency.
- [ ] Measure input p95 latency.
- [ ] Measure preview render latency.
- [ ] Measure memory during long terminal/editor session.
- [ ] Add stale render discard tests.

## P2 Checklist

### Recent Workspace Persistence

Requirements: `WS-5`

- [ ] Persist recent workspace list to Application Support or UserDefaults.
- [ ] Restore recent list on app launch.
- [ ] Add UI affordance to reopen recent workspace.

### Polish and Product Completion

Requirements: `TM-7`, `MD-6`, `VT-4`, `NT-5`

- [ ] Terminal theme/font policy.
- [ ] External link opening policy.
- [ ] Last notification snippet in session rows.
- [ ] Keyboard action to jump to latest notification.

### Distribution

Requirements: `DS-1` to `DS-4`

- [ ] Open-source readiness pass.
- [ ] Release build process.
- [ ] Apple notarization plan.
- [ ] Distribution documentation.

## Open Decisions

- [ ] Terminal renderer: embed existing terminal engine or implement minimal renderer.
- [ ] Markdown renderer: Swift-native parser or WebView/unified HTML pipeline.
- [ ] File access: keep sandbox off for MVP or adopt sandbox on with security-scoped bookmarks.
- [ ] Codex/Claude detection: exact output patterns and hook payload contract.
- [ ] Command palette: keep out of MVP unless user explicitly prioritizes it.
- [ ] Session restore policy: restore all terminal/document metadata or only pinned sessions.

## Recommended Next Work Slice

Start with `P0-1. File Tree MVP`.

Reason:

- It is required before a natural document-open flow exists.
- It has clear boundaries and lower risk than PTY/WebKit.
- It unlocks editor and preview work without forcing terminal decisions.
- It can be verified with deterministic unit tests.

Expected first DEV step:

- Present 3 implementation options for `FileTreeStore` and left rail integration.
- Include exact files to add/modify.
- Wait for user approval before editing code.
