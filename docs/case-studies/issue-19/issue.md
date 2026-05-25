# Issue #19: Reorganize Project to Reduce Merge Conflicts

## Issue Description

**Author:** Jhon-Crow  
**URL:** https://github.com/Jhon-Crow/candy-crush-tetris-godot-game/issues/19  
**Title:** организуй проект так чтоб было меньше конфликтов

**Summary (translated from Russian):**
Split the project into different files. When something needs to be added, add a new file and connect it where needed. It's better to have more files but fewer conflicts. Use OOP, but don't break what already works. Add tests for OOP-ness and existing functionality.

## Current State Analysis

The entire game is currently in a single monolithic file: `scripts/Game.gd` (~666 lines).

### Issues with Monolithic Architecture

1. **Merge Conflicts:** Any change to any part of the game (physics, AI, visuals, effects) requires editing the same file, causing conflicts when multiple PRs are open simultaneously.
2. **Poor Separation of Concerns:** Board logic, rendering, AI, special effects, and HUD are all mixed together.
3. **Hard to Extend:** Adding new features requires modifying the same large file.
4. **Poor Testability:** Can't test individual components in isolation.

### Current Class Structure

- `extends Node3D` — single monolithic `Game.gd`
- Contains: board state, piece management, special effects, auto-player AI, HUD, scene construction
