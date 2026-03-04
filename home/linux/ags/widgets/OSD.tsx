import { Astal, Gtk, Gdk } from "ags/gtk3";
import { createState } from "ags";
import { timeout } from "ags/time";
import Wp from "gi://AstalWp";
import { readFile } from "../lib/utils";

const [osdVisible, setOsdVisible] = createState(false);
const [osdValue, setOsdValue] = createState(0);
const [osdIcon, setOsdIcon] = createState("");
let hideTimeout: any = null;

function getVolumeIcon(speaker: any): string {
  if (speaker.mute) return "\uf6a9"; //
  const vol = speaker.volume;
  if (vol < 0.33) return "\uf026"; //
  if (vol < 0.66) return "\uf027"; //
  return "\uf028"; //
}

function getBrightness(): number {
  const brightness = readFile("/sys/class/backlight/amdgpu_bl2/brightness");
  const maxBrightness = readFile("/sys/class/backlight/amdgpu_bl2/max_brightness");
  if (!brightness || !maxBrightness) return 0;
  return Math.round((parseInt(brightness) / parseInt(maxBrightness)) * 100);
}

export function showOSD(type: string) {
  if (type === "volume") {
    const speaker = Wp.get_default()?.audio?.defaultSpeaker;
    if (!speaker) return;
    setOsdValue(Math.round(speaker.volume * 100));
    setOsdIcon(getVolumeIcon(speaker));
  } else if (type === "brightness") {
    const pct = getBrightness();
    setOsdValue(pct);
    setOsdIcon("\uf185"); //
  } else if (type === "mic") {
    const mic = Wp.get_default()?.audio?.defaultMicrophone;
    if (!mic) return;
    setOsdValue(Math.round(mic.volume * 100));
    setOsdIcon(mic.mute ? "\uf131" : "\uf130"); //  or
  }

  setOsdVisible(true);

  if (hideTimeout) {
    hideTimeout.cancel();
    hideTimeout = null;
  }

  hideTimeout = timeout(1500, () => {
    setOsdVisible(false);
    hideTimeout = null;
  });
}

function OSD() {
  return (
    <window
      name="osd"
      class="osd-popup"
      layer={Astal.Layer.OVERLAY}
      anchor={Astal.WindowAnchor.BOTTOM}
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={osdVisible}
      keymode={Astal.Keymode.NONE}
    >
      <box class="osd-container" spacing={12} valign={Gtk.Align.CENTER}>
        <label
          class="osd-icon"
          label={osdIcon}
          widthChars={2}
          halign={Gtk.Align.CENTER}
        />
        <Gtk.LevelBar
          class="osd-bar"
          minValue={0}
          maxValue={100}
          value={osdValue}
          hexpand
          valign={Gtk.Align.CENTER}
        />
        <label
          class="osd-value"
          label={osdValue.as((v) => `${v}%`)}
          widthChars={4}
          xalign={1}
        />
      </box>
    </window>
  );
}

export default OSD;
