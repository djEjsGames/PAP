extends SceneTree

const Dump := preload("res://scripts/paper_dump.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Usage: --script res://tests/validate_dump.gd -- <dump.json>")
		quit(2)
		return
	var file := FileAccess.open(args[0], FileAccess.READ)
	if file == null:
		printerr("Cannot open dump: ", args[0])
		quit(2)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		printerr("Invalid JSON dump")
		quit(2)
		return
	var snapshot: Dictionary = Dump.decode(json.data)
	var report := Dump.validate(snapshot)
	print(JSON.stringify(report, "  "))
	quit(0 if report.valid else 1)
