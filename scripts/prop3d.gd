@tool
extends Sprite3D

# Editor-placeable rooftop prop. Drop scenes/prop3d.tscn into a scene, then in the
# Inspector pick `prop_index` (0..5) and `height`; drag it around with the gizmo.
# The sprite's BOTTOM sits on the node origin, so place it on the floor at Y=0.
#
#   0 = AC/HVAC unit   1 = water tank   2 = satellite dish
#   3 = SYNTH-RAMEN neon sign   4 = ammo crates   5 = road barrier

const ART := "res://assets/sprites/citymap/"

@export_range(0, 5) var prop_index := 0:
	set(v):
		prop_index = v
		_apply()

@export var height := 5.0:
	set(v):
		height = v
		_apply()

func _ready() -> void:
	_apply()

func _apply() -> void:
	var t: Texture2D = load(ART + "prop_%d.png" % prop_index)
	if t == null:
		return
	texture = t
	pixel_size = height / float(t.get_height())
	offset = Vector2(0.0, float(t.get_height()) * 0.5)  # pivot at the base
	centered = true
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	shaded = false
