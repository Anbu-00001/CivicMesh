"""Replay step logic for GraphViz."""

impl GraphViz.startReplay -> None {
    is_playing = True;
    visited = [];
    current = "";
    replay_idx = 0;
    stepReplay();
}

impl GraphViz.stepReplay -> None {
    if replay_idx >= len(walk_path) {
        is_playing = False;
        current = "";
        return;
    }
    current = walk_path[replay_idx];
    visited = walk_path[:replay_idx + 1];
    replay_idx = replay_idx + 1;
}
