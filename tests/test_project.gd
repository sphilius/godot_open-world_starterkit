extends TestCase
## Project-wide gate. `godot --import` exits 0 even when a script doesn't parse, so this test
## loads every script and scene; the runner fails it on any error logged while loading.

const SKIP_DIRS: Array[String] = ["res://.godot", "res://build"]


func test_every_script_compiles() -> void:
	var scripts := _files_with_extension("res://", "gd")
	expect(scripts.size() > 10, "found only %d scripts" % scripts.size())
	for path in scripts:
		var script := load(path) as GDScript
		expect(script != null and script.can_instantiate(), "%s doesn't compile" % path)


func test_every_scene_loads() -> void:
	for path in _files_with_extension("res://", "tscn"):
		expect(load(path) is PackedScene, "%s doesn't load" % path)


func _files_with_extension(dir: String, extension: String) -> PackedStringArray:
	var found := PackedStringArray()
	if dir in SKIP_DIRS or FileAccess.file_exists(dir.path_join(".gdignore")):
		return found
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == extension:
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			found.append_array(_files_with_extension(dir.path_join(sub), extension))
	return found
