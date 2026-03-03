import { App, Astal, Gtk, Gdk } from "astal/gtk3";
import { bind, Variable, interval } from "astal";
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
  const position = Variable(player.position);

  const tick = interval(1000, () => {
    if (player.playbackStatus === Mpris.PlaybackStatus.PLAYING) {
      position.set(player.position);
    }
  });

  // Also sync when position changes externally (seek, track change)
  player.connect("notify::position", () => {
    position.set(player.position);
  });

  return (
    <box
      className="media-content"
      vertical
      onDestroy={() => tick.cancel()}
    >
      <box className="album-art-container">
        <box
          className="album-art"
          css={bind(player, "coverArt").as(
            (art) =>
              art
                ? `background-image: url("${art}"); background-size: cover; background-position: center; min-width: 200px; min-height: 200px;`
                : `min-width: 200px; min-height: 200px;`,
          )}
        />
      </box>

      <box className="track-info" vertical>
        <label
          className="track-title"
          label={bind(player, "title").as((t) => t || "Unknown Title")}
          truncate
          maxWidthChars={30}
          xalign={0}
        />
        <label
          className="track-artist"
          label={bind(player, "artist").as((a) => a || "Unknown Artist")}
          truncate
          maxWidthChars={30}
          xalign={0}
        />
        <label
          className="track-album"
          label={bind(player, "album").as((a) => a || "")}
          truncate
          maxWidthChars={30}
          xalign={0}
          visible={bind(player, "album").as((a) => !!a)}
        />
      </box>

      <box className="progress-bar" vertical>
        <slider
          className="progress-slider"
          drawValue={false}
          min={0}
          max={bind(player, "length").as((l) => (l > 0 ? l : 1))}
          value={bind(position)}
          onDragged={({ value }) => {
            player.set_position(value);
            position.set(value);
          }}
        />
        <box className="progress-times" homogeneous={false}>
          <label
            className="progress-elapsed"
            label={bind(position).as(formatTime)}
            hexpand
            xalign={0}
          />
          <label
            className="progress-total"
            label={bind(player, "length").as(formatTime)}
            xalign={1}
          />
        </box>
      </box>

      <box className="media-controls" halign={Gtk.Align.CENTER}>
        <button
          className={bind(player, "shuffleStatus").as(
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
          className="previous"
          sensitive={bind(player, "canGoPrevious")}
          onClick={() => player.previous()}
        >
          <label label="&#xf048;" />
        </button>

        <button
          className="play-pause"
          onClick={() => player.play_pause()}
        >
          <label
            label={bind(player, "playbackStatus").as((s) =>
              s === Mpris.PlaybackStatus.PLAYING
                ? "\uf04c"
                : "\uf04b",
            )}
          />
        </button>

        <button
          className="next"
          sensitive={bind(player, "canGoNext")}
          onClick={() => player.next()}
        >
          <label label="&#xf051;" />
        </button>

        <button
          className={bind(player, "loopStatus").as(
            (s) => (s !== Mpris.Loop.NONE ? "loop active" : "loop"),
          )}
          onClick={() => cycleLoop(player)}
        >
          <label
            label={bind(player, "loopStatus").as(loopIconFor)}
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
      className="media-popup"
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
      <box className="media-container" vertical>
        {bind(mpris, "players").as((players) =>
          players.length > 0 ? (
            <PlayerView player={players[0]} />
          ) : (
            <box
              className="no-media"
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
