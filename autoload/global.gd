extends Node

const FLASH_MATERIAL = preload("uid://b6nlq50nu48th")

var player: Player

func get_chance_sucess(chance: float) -> bool:
	var random := randf_range(0, 1.0)
	if random < chance:
		return true
	return false
