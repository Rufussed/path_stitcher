# GodotLiveMCP: Inspector tools proposal

For the agent that maintains GodotLiveMCP. Written from a real session that built a custom Inspector UI (an `EditorInspectorPlugin`) for the PathStitcher node, entirely through the bridge.

## Summary

Building the Inspector UI was possible through `run_script` and `edit_script_text`, but the agent could not see the result or operate it. Everything below is about closing that gap. We propose **four small tools**. We deliberately do not propose a UI generator or a widget library: an agent can already write the GDScript, and what it lacks is eyes and hands.

## What worked, and what hurt

- Worked: writing the plugin with `edit_script_text`, reading state with `run_script`.
- Hurt: the agent could not see the Inspector. It had to hand-build a screenshot through `run_script`, and checked layout by guessing from code.
- Hurt: a user wanted columns aligned. Only measuring control positions (`global_position.x` of every row's picker) proved it. That should be one tool call.
- Hurt: hot-reload and plugin-state traps (list at the end) cost many round trips.

## Proposed tools

### 1. `get_inspector_screenshot`

Returns a PNG of the Inspector dock (or any editor dock) so the agent can look at a custom UI.

- Params: `target` (`"inspector"` default, or `"scene_tree"`, `"filesystem"`, `"bottom_panel"`, `"editor"`), optional `max_height`.
- Verified recipe (works today in `run_script`): take `EditorInterface.get_base_control().get_viewport().get_texture().get_image()`, crop to `Rect2i(EditorInterface.get_inspector().get_global_rect())` clamped to the image, save as PNG. Note the image is in physical pixels and the editor scale may be 2.0.
- Why it is worth a tool: the existing `get_editor_screenshot` is the nearest thing, but a cropped dock at full resolution is what UI work needs. If `get_editor_screenshot` already accepts a region or a node, extend it instead and drop this tool.

### 2. `dump_control_tree`

Returns the live Control tree under a root as compact JSON, so the agent can check layout numerically.

- Params: `root` (`"inspector"` default, or a node path in the editor UI), `max_depth`, `filter_script` (only subtrees whose script path matches, for example `building_blocks_editor.gd`).
- Per control: class, script path, `text` / tooltip, `global_position`, `size`, `visible`, `disabled`, child count, and a stable `path` (for example `VBox/HBox[2]/Button[0]`) usable by tool 3.
- Why: confirms alignment ("all pickers at x=2925"), finds a missing control, and shows which row a button belongs to without a screenshot.

### 3. `interact_control`

Operates a control found by tool 2 so the agent can test a custom UI end to end, including its undo behaviour.

- Params: `path` (from `dump_control_tree`) or `text` + `class` match, and an `action`: `press`, `set_value` (SpinBox, CheckBox, OptionButton index, LineEdit), `select_menu_item` (MenuButton / PopupMenu by id or text), `drop_files` (simulate a FileSystem-dock drop by calling the control's `_can_drop_data` / `_drop_data` with `{"type":"files","files":[...]}`).
- Returns the control's state afterwards and whether the editor undo history gained an action.
- Why: in the session every UI behaviour (add a block via the empty slot, reorder by drag, drop several files, Ctrl+Z) could only be verified by asking the human. Pressing and dropping programmatically lets the agent verify its own work.
- Note: drag-reorder is two calls (`_get_drag_data` on the source, `_drop_data` on the target); a `drag_drop` action with `from` and `to` paths would be the simplest form.

### 4. `refresh_editor_scripts`

One call that does the reload dance correctly after `edit_script_text` edits to `@tool` scripts, addons and resource scripts.

Steps it should perform, in order:
1. `ScriptEditor.save_all_scripts()` (edit_script_text leaves files unsaved).
2. Re-parse the given scripts (`ResourceLoader.load(path, "", CACHE_MODE_REPLACE)` then `reload(true)`) and **return parse errors**, since a plugin enabled against a broken script silently does nothing.
3. If an EditorPlugin under `res://addons/` is among them, toggle it (`EditorInterface.set_plugin_enabled` off, then on).
4. Re-select the current node (`edit_node`) so the Inspector is rebuilt.
5. Report members added to a script that now read `null` on existing instances (see the gotchas), so the agent knows to set them.

`reload_plugin` exists; this tool would absorb it and add steps 1, 2, 4 and 5.

## Not proposed (and why)

- An Inspector-plugin generator or DSL: the agent writes GDScript directly, and a DSL would be a second thing to learn and maintain.
- A shared widget library (boxed sections, reorderable rows): useful, but belongs in the user's project or an addon, not in the MCP.
- Generic mouse-coordinate clicking in the editor: `interact_control` by path is more robust than pixel clicks.

## Acceptance test

With the PathStitcher project open and a `PathStitcher` selected, an agent should be able to: (1) screenshot the Inspector, (2) dump the controls and verify that the First, Last and block-row scene pickers share one x, (3) drop a `.blend` onto the empty slot via `interact_control` and see a new block row plus a new empty slot, (4) confirm one undo step was added, (5) edit the editor script and call `refresh_editor_scripts` with no parse error and a rebuilt Inspector.

## Gotchas learned (candidates for tool output or docs)

- A helper named `_set` in an editor script clashes with `Object._set`; the parse error is unhelpful. Name helpers `_apply`.
- `edit_script_text` does not save; the Inspector plugin keeps running the old file on disk until `save_all_scripts()`.
- A plugin enabled while one of its scripts failed to parse stays inert; disable and re-enable after fixing.
- Hot-reloading a resource script that gains a member leaves it `null` on existing instances, and reloading the scene does not help because sub-resources are cached; set the value through a script or restart the editor.
- `EditorResourcePicker` shows a large thumbnail for `PackedScene`, making rows tall; a custom Button + MenuButton picker is one line.
- Fixed pixel widths in custom UI must be multiplied by `EditorInterface.get_editor_scale()` (it was 2.0 here).
- A custom Inspector control built in `_parse_property` should refresh from `EditorUndoRedoManager.version_changed` and guard its own edits so it does not rebuild mid-edit.
