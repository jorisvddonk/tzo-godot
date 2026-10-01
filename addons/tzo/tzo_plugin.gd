@tool
## Editor plugin entry point for the Tzo addon.
##
## The addon only provides runtime classes ([TzoVM] and [QuestVM]); there is no
## editor UI, so this plugin exists purely to make the addon visible/enable-able
## in the editor's plugin list.
extends EditorPlugin


func _enter_tree() -> void:
	pass


func _exit_tree() -> void:
	pass
