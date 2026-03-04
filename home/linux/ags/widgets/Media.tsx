import { Astal, Gtk, Gdk } from "ags/gtk3";
import { createBinding, createState } from "ags";
import { interval } from "ags/time";
import Mpris from "gi://AstalMpris";
import { registerPopup } from "../lib/popups";

function formatTime(seconds: number): string {
  if (!seconds || seconds < 0) return "0:00";
  const mins = Math.floor(seconds / 60);
  const secs = Math.floor(seconds % 60);
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

function loopIconFor(status: Mpris.Loop): string {
  switch (status) {
    case Mpris.Loop.TRACK:
      return "\uf021"; // repeat-one equivalent
    case Mpris.Loop.PLAYLIST:
      return "\uf079"; // repeat
    default:
      return "\uf079"; // repeat (dimmed via class)
  }
}

function cycleLoop(player: Mpris.Player) {
  switch (player.loopStatus) {
    case Mpris.Loop.NONE:
      player.loopStatus = Mpris.Loop.PLAYLIST;
      break;
    case Mpris.Loop.PLAYLIST:
      player.loopStatus = Mpris.Loop.TRACK;
      break;
    default:
      player.loopStatus = Mpris.Loop.NONE;
      break;
  }
}

function PlayerView({ player }: { player: Mpris.Player }) {
  const [position, setPosition] = createState(player.position);

  const tick = interval(1000, () => {
    if (player.playbackStatus === Mpris.PlaybackStatus.PLAYING) {
      setPosition(player.position);
    }
  });

  // Also sync when position changes externally (seek, track change)
  player.connect("notify::position", () => {
    setPosition(player.position);
  });

  return (
    <box
      class="media-content"
      vertical
      onDestroy={() => tick.cancel()}
    >
      <box class="album-art-container">
        <box
          class="album-art"
          css={createBinding(player, "coverArt").as(
            (art) =>
              art
                ? `background-image: url("${art}"); background-size: cover; background-position: center; min-width: 200px; min-height: 200px;`
                : `min-width: 200px; min-height: 200px;`,
          )}
        />
      </box>

      <box class="track-info" vertical>
        <label
          class="track-title"
          label={createBinding(player, "title").as((t) => t || "Unknown Title")}
          truncate
          maxWidthChars={30}
          xalign={0}
        />
        <label
          class="track-artist"
          label={createBinding(player, "artist").as((a) => a || "Unknown Artist")}
          truncate
          maxWidthChars={30}
          xalign={0}
        />
        <label
          class="track-album"
          label={createBinding(player, "album").as((a) => a || "")}
          truncate
          maxWidthChars={30}
          xalign={0}
          visible={createBinding(player, "album").as((a) => !!a)}
        />
      </box>

      <box class="progress-bar" vertical>
        <slider
          class="progress-slider"
          drawValue={false}
          min={0}
          max={createBinding(player, "length").as((l) => (l > 0 ? l : 1))}
          value={position}
          onDragged={({ value }) => {
            player.set_position(value);
            setPosition(value);
          }}
        />
        <box class="progress-times" homogeneous={false}>
          <label
            class="progress-elapsed"
            label={position.as(formatTime)}
            hexpand
            xalign={0}
          />
          <label
            class="progress-total"
            label={createBinding(player, "length").as(formatTime)}
            xalign={1}
          />
        </box>
      </box>

      <box class="media-controls" halign={Gtk.Align.CENTER}>
        <button
          class={createBinding(player, "shuffleStatus").as(
            (s) => (s === Mpris.Shuffle.ON ? "shuffle active" : "shuffle"),
          )}
          onClick={() => {
            player.shuffleStatus =
              player.shuffleStatus === Mpris.Shuffle.ON
                ? Mpris.Shuffle.OFF
                : Mpris.Shuffle.ON;
          }}
        >
          <label label="&#xf074;" />
        </button>

        <button
          class="previous"
          sensitive={createBinding(player, "canGoPrevious")}
          onClick={() => player.previous()}
        >
          <label label="&#xf048;" />
        </button>

        <button
          class="play-pause"
          onClick={() => player.play_pause()}
        >
          <label
            label={createBinding(player, "playbackStatus").as((s) =>
              s === Mpris.PlaybackStatus.PLAYING
                ? "\uf04c"
                : "\uf04b",
            )}
          />
        </button>

        <button
          class="next"
          sensitive={createBinding(player, "canGoNext")}
          onClick={() => player.next()}
        >
          <label label="&#xf051;" />
        </button>

        <button
          class={createBinding(player, "loopStatus").as(
            (s) => (s !== Mpris.Loop.NONE ? "loop active" : "loop"),
          )}
          onClick={() => cycleLoop(player)}
        >
          <label
            label={createBinding(player, "loopStatus").as(loopIconFor)}
          />
        </button>
      </box>
    </box>
  );
}

function MediaPlayer() {
  const mpris = Mpris.get_default();

  return (
    <window
      name="media"
      class="media-popup"
      layer={Astal.Layer.OVERLAY}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT}
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={false}
      keymode={Astal.Keymode.ON_DEMAND}
      setup={(self) => registerPopup("media", self)}
      onKeyPressEvent={(self, event) => {
        const [, keyval] = event.get_keyval();
        if (keyval === Gdk.KEY_Escape) {
          self.visible = false;
        }
      }}
    >
      <box class="media-container" vertical>
        {createBinding(mpris, "players").as((players) =>
          players.length > 0 ? (
            <PlayerView player={players[0]} />
          ) : (
            <box
              class="no-media"
              halign={Gtk.Align.CENTER}
              valign={Gtk.Align.CENTER}
            >
              <label label="No media playing" />
            </box>
          ),
        )}
      </box>
    </window>
  );
}

export default MediaPlayer;
