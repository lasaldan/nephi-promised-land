extends Node

# Autoload. Signals that cross the scene: the backpack, quests and activities.
# A chapter should not wait on these directly: they outlive the world, so a
# chapter left waiting when the player quits to the menu would wake in the next
# game. world.gd passes the ones chapters need on as its own signals.

signal player_inventory_change
# Only for a pickup that went into the backpack, not for emptying it.
signal player_item_added(item: InventoryItem)
# What emptying the backpack took out, such as fruit left at a crate. Not sent
# for the reset when a game starts.
signal player_items_removed(items: Array[InventoryItem])

# quest_id matches StoryChapter.ends_on. A side quest uses its own id and does
# not advance the chapter.
signal quest_completed(quest_id: String)

# An activity on the scroll was finished (ui/activity_scroll.gd). activity_id
# is its key in ActivityScroll.BOARDS.
signal activity_finished(activity_id: String)
# A stage of that activity is done while its scroll stays open, such as one
# log of a sawing (ScrollBoard.step_done). step counts from 0.
signal activity_step(activity_id: String, step: int)
