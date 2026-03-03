import { App, Astal, Gtk, Gdk } from "astal/gtk3";
import { Variable, timeout } from "astal";
import Wp from "gi://AstalWp";
import { readFile } from "../lib/utils";

const osdVisible = Variable(false);
const osdValue = Variable(0);
const osdIcon = Variable("");
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
    osdValue.set(Math.round(speaker.volume * 100));
    osdIcon.set(getVolumeIcon(speaker));
  } else if (type === "brightness") {
    const pct = getBrightness();
    osdValue.set(pct);
    osdIcon.set("\uf185"); //
  } else if (type === "mic") {
    const mic = Wp.get_default()?.audio?.defaultMicrophone;
    if (!mic) return;
    osdValue.set(Math.round(mic.volume * 100));
    osdIcon.set(mic.mute ? "\uf131" : "\uf130"); //  or
  }

  osdVisible.set(true);

  if (hideTimeout) {
    hideTimeout.cancel();
    hideTimeout = null;
  }

  hideTimeout = timeout(1500, () => {
    osdVisible.set(false);
    hideTimeout = null;
  });
}

function OSD() {
  return (
    <window
      name="osd"
      className="osd-popup"
      layer={Astal.Layer.OVERLAY}
      anchor={Astal.WindowAnchor.BOTTOM}
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={osdVisible()}
      keymode={Astal.Keymode.NONE}
    >
      <box className="osd-container" spacing={12} valign={Gtk.Align.CENTER}>
        <label
          className="osd-icon"
          label={osdIcon()}
          widthChars={2}
          halign={Gtk.Align.CENTER}
        />
        <Gtk.LevelBar
          className="osd-bar"
          minValue={0}
          maxValue={100}
          value={osdValue()}
          hexpand
          valign={Gtk.Align.CENTER}
        />
        <label
          className="osd-value"
          label={osdValue((v) => `${v}%`)}
          widthChars={4}
          xalign={1}
        />
      </box>
    </window>
  );
}

export default OSD;
