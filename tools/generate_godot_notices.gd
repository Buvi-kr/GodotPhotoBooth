extends SceneTree

const OUTPUT_PATH := "res://licenses/Godot-Third-Party.txt"

func _initialize() -> void:
    var lines := PackedStringArray()
    var version := Engine.get_version_info()
    lines.append("Godot Engine %s.%s.%s third-party notices" % [version.major, version.minor, version.patch])
    lines.append("Generated from Engine.get_copyright_info() and Engine.get_license_info().")
    lines.append("This list describes the bundled Godot engine; it does not change the licenses of this project's own code or assets.")
    lines.append("")
    lines.append("COMPONENT COPYRIGHTS")
    lines.append("=====================")
    for component in Engine.get_copyright_info():
        lines.append("")
        lines.append(str(component.get("name", "Third-party component")))
        for part in component.get("parts", []):
            lines.append("  Copyright: " + "; ".join(PackedStringArray(part.get("copyright", []))))
            lines.append("  Files: " + ", ".join(PackedStringArray(part.get("files", []))))
            lines.append("  License: " + str(part.get("license", "")))
    lines.append("")
    lines.append("LICENSE TEXTS")
    lines.append("=============")
    var license_info: Dictionary = Engine.get_license_info()
    var names := PackedStringArray()
    for license_name in license_info.keys():
        names.append(str(license_name))
    names.sort()
    for license_name in names:
        lines.append("")
        lines.append("--- " + license_name + " ---")
        lines.append(str(license_info[license_name]))
    var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if file == null:
        push_error("Could not write Godot third-party notices: " + OUTPUT_PATH)
        quit(1)
        return
    file.store_string("\n".join(lines) + "\n")
    print("Generated Godot third-party notices for %s.%s.%s (%d components, %d licenses)." % [version.major, version.minor, version.patch, Engine.get_copyright_info().size(), license_info.size()])
    quit()