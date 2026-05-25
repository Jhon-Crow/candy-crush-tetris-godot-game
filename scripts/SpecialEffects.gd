class_name SpecialEffects
## Applies Candy-Crush-style special-ball effects to a [Board].
##
## Each effect method modifies the board in place and returns void.
## Callers are responsible for incrementing any counters and updating the HUD.

## Emitted after any effect fires, so the HUD can refresh.
signal effect_triggered

## Emitted when the freeze effect activates; carries the duration in seconds.
signal freeze_activated(duration: float)


# --- Effect methods ----------------------------------------------------------

## BOMB: clears all settled cells within a Chebyshev [param radius] of [param center].
func apply_bomb(board: Board, center: Vector2i, radius: int) -> void:
	board.clear_chebyshev(center, radius)
	effect_triggered.emit()


## RAINBOW: clears every settled ball whose color matches any color in [param piece_colors].
func apply_rainbow(board: Board, piece_colors: Array) -> void:
	board.clear_by_colors(piece_colors)
	effect_triggered.emit()


## FREEZE: activates the slow-fall effect for [param duration] seconds.
## The game controller handles the timer; this just signals it.
func apply_freeze(duration: float) -> void:
	freeze_activated.emit(duration)
	effect_triggered.emit()


## LIGHTNING: clears every settled ball in [param col].
func apply_lightning(board: Board, col: int) -> void:
	board.clear_column(col)
	effect_triggered.emit()
