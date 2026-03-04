import { Astal, Gtk, Gdk } from "ags/gtk3";
import { createBinding } from "ags";
import Wp from "gi://AstalWp";
import { registerPopup } from "../lib/popups";

const wp = Wp.get_default()!;
const audio = wp.audio;

function VolumeSlider({
  endpoint,
  label,
  showMute = false,
}: {
  endpoint: Wp.Endpoint;
  label: string;
  showMute?: boolean;
}) {
  return (
    <box class="volume-row" vertical={false} spacing={8}>
      <label
        class="volume-label"
        label={label}
        xalign={0}
        truncate
        maxWidthChars={16}
        widthRequest={120}
      />
      <slider
        class="volume-slider"
        hexpand
        value={createBinding(endpoint, "volume")}
        onDragged={(self) => {
          endpoint.volume = self.value;
        }}
      />
      <label
        class="volume-percent"
        label={createBinding(endpoint, "volume").as((v) =>
          `${Math.round(v * 100)}%`
        )}
        widthRequest={48}
      />
      {showMute && (
        <button
          class={createBinding(endpoint, "mute").as((m) =>
            m ? "mute-btn muted" : "mute-btn"
          )}
          onClicked={() => {
            endpoint.mute = !endpoint.mute;
          }}
        >
          <label
            label={createBinding(endpoint, "mute").as((m) =>
              m ? "󰍭" : "󰍬"
            )}
          />
        </button>
      )}
    </box>
  );
}

function MasterSection() {
  const speaker = audio.defaultSpeaker;

  return (
    <box class="mixer-section" vertical spacing={4}>
      <label class="section-title" label="Output Volume" xalign={0} />
      <box class="volume-row" vertical={false} spacing={8}>
        <label
          class="volume-icon"
          label={createBinding(speaker, "volume").as((v) =>
            v === 0 ? "󰝟" : v < 0.33 ? "󰕿" : v < 0.66 ? "󰖀" : "󰕾"
          )}
        />
        <slider
          class="volume-slider"
          hexpand
          value={createBinding(speaker, "volume")}
          onDragged={(self) => {
            speaker.volume = self.value;
          }}
        />
        <label
          class="volume-percent"
          label={createBinding(speaker, "volume").as((v) =>
            `${Math.round(v * 100)}%`
          )}
          widthRequest={48}
        />
        <button
          class={createBinding(speaker, "mute").as((m) =>
            m ? "mute-btn muted" : "mute-btn"
          )}
          onClicked={() => {
            speaker.mute = !speaker.mute;
          }}
        >
          <label
            label={createBinding(speaker, "mute").as((m) =>
              m ? "󰖁" : "󰕾"
            )}
          />
        </button>
      </box>
    </box>
  );
}

function AppStreams() {
  const streams = createBinding(audio, "streams");

  return (
    <box class="mixer-section" vertical spacing={4}>
      <label class="section-title" label="Applications" xalign={0} />
      {streams.as((list) => {
        if (list.length === 0) {
          return (
            <label
              class="no-streams"
              label="No audio applications running"
              xalign={0}
            />
          );
        }
        return list.map((stream) => (
          <VolumeSlider
            endpoint={stream}
            label={createBinding(stream, "description").as((d) => d ?? "Unknown")}
          />
        ));
      })}
    </box>
  );
}

function OutputDevices() {
  const speakers = createBinding(audio, "speakers");
  const defaultSpeaker = audio.defaultSpeaker;

  return (
    <box class="mixer-section device-list" vertical spacing={4}>
      <label class="section-title" label="Output Devices" xalign={0} />
      {speakers.as((list) =>
        list.map((device) => (
          <button
            class={createBinding(defaultSpeaker, "id").as((id) =>
              device.id === id ? "device-item active" : "device-item"
            )}
            onClicked={() => {
              device.set_is_default(true);
            }}
          >
            <box spacing={8}>
              <label class="device-icon" label="󰓃" />
              <label
                class="device-name"
                label={createBinding(device, "description").as((d) => d ?? "Unknown")}
                xalign={0}
                truncate
                hexpand
              />
            </box>
          </button>
        ))
      )}
    </box>
  );
}

function InputSection() {
  const mic = audio.defaultMicrophone;

  return (
    <box class="mixer-section" vertical spacing={4}>
      <label class="section-title" label="Input" xalign={0} />
      <box class="volume-row" vertical={false} spacing={8}>
        <label
          class="volume-icon"
          label={createBinding(mic, "mute").as((m) => (m ? "󰍭" : "󰍬"))}
        />
        <slider
          class="volume-slider"
          hexpand
          value={createBinding(mic, "volume")}
          onDragged={(self) => {
            mic.volume = self.value;
          }}
        />
        <label
          class="volume-percent"
          label={createBinding(mic, "volume").as((v) =>
            `${Math.round(v * 100)}%`
          )}
          widthRequest={48}
        />
        <button
          class={createBinding(mic, "mute").as((m) =>
            m ? "mute-btn muted" : "mute-btn"
          )}
          onClicked={() => {
            mic.mute = !mic.mute;
          }}
        >
          <label
            label={createBinding(mic, "mute").as((m) =>
              m ? "󰍭" : "󰍬"
            )}
          />
        </button>
      </box>
      <box class="device-list" vertical spacing={2}>
        {createBinding(audio, "microphones").as((list) =>
          list.map((device) => (
            <button
              class={createBinding(mic, "id").as((id) =>
                device.id === id ? "device-item active" : "device-item"
              )}
              onClicked={() => {
                device.set_is_default(true);
              }}
            >
              <box spacing={8}>
                <label class="device-icon" label="󰍬" />
                <label
                  class="device-name"
                  label={createBinding(device, "description").as(
                    (d) => d ?? "Unknown"
                  )}
                  xalign={0}
                  truncate
                  hexpand
                />
              </box>
            </button>
          ))
        )}
      </box>
    </box>
  );
}

function AudioMixer() {
  return (
    <window
      name="audiomixer"
      layer={Astal.Layer.OVERLAY}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT}
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={false}
      keymode={Astal.Keymode.EXCLUSIVE}
      $={(self) => registerPopup("audiomixer", self)}
      onKeyPressEvent={(self, event) => {
        if (event.get_keyval()[1] === Gdk.KEY_Escape) {
          self.visible = false;
        }
      }}
    >
      <eventbox
        hexpand
        vexpand
        onClick={(self) => { self.get_toplevel().visible = false; }}
      >
        <box hexpand vexpand halign={Gtk.Align.END} valign={Gtk.Align.START}>
          <eventbox onClick={() => true}>
            <box class="audiomixer-popup" vertical spacing={12}>
              <MasterSection />
              <AppStreams />
              <OutputDevices />
              <InputSection />
            </box>
          </eventbox>
        </box>
      </eventbox>
    </window>
  );
}

export default AudioMixer;
