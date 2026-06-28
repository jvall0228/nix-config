import { Astal, Gtk } from "ags/gtk3";
import { createState } from "ags";
import { createPoll } from "ags/time";

// Agent-mode lock curtain (R17) — a NON-locking AGS overlay that replicates the
// hyprlock scene so agent-mode looks identical to a real lock, while the agents'
// off-screen stage stays capturable. (The pixel-perfect "fork hyprlock" route is
// deferred — see todos/007.) Toggled by the cua daemon via `ags request agentlock
// show|hide` in place of the old kitty curtain. AGS is software-rendered here, so
// this layer-shell surface paints fine on the hybrid GPU.

const [visible, setVisible] = createState(false);
export function showAgentLock() {
  setVisible(true);
}
export function hideAgentLock() {
  setVisible(false);
}

// Same content hyprlock shows in its time/date labels.
const clockTime = createPoll("", 1000, ["date", "+%H:%M"]);
const clockDate = createPoll("", 1000, ["date", "+%A %b %d"]);

function AgentLock() {
  return (
    <window
      name="agentlock"
      class="agentlock"
      layer={Astal.Layer.OVERLAY}
      anchor={
        Astal.WindowAnchor.TOP |
        Astal.WindowAnchor.BOTTOM |
        Astal.WindowAnchor.LEFT |
        Astal.WindowAnchor.RIGHT
      }
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={visible}
      keymode={Astal.Keymode.NONE}
    >
      <box class="agentlock-bg" hexpand vexpand>
        <box
          class="agentlock-scene"
          vertical
          hexpand
          vexpand
          halign={Gtk.Align.CENTER}
          valign={Gtk.Align.START}
        >
          <label class="agentlock-time" label={clockTime} />
          <label class="agentlock-date" label={clockDate} />
        </box>
      </box>
    </window>
  );
}

export default AgentLock;
