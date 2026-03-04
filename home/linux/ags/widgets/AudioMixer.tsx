import { App, Astal, Gtk, Gdk } from "astal/gtk3";
import { bind, Variable } from "astal";
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
    <box className="volume-row" vertical={false} spacing={8}>
      <label
        className="volume-label"
        label={label}
        xalign={0}
        truncate
        maxWidthChars={16}
        widthRequest={120}
      />
      <slider
        className="volume-slider"
        hexpand
        value={bind(endpoint, "volume")}
        onDragged={(self) => {
          endpoint.volume = self.value;
        }}
      />
      <label
        className="volume-percent"
        label={bind(endpoint, "volume").as((v) =>
          `${Math.round(v * 100)}%`
        )}
        widthRequest={48}
      />
      {showMute && (
        <button
          className={bind(endpoint, "mute").as((m) =>
            m ? "mute-btn muted" : "mute-btn"
          )}
          onClicked={() => {
            endpoint.mute = !endpoint.mute;
          }}
        >
          <label
            label={bind(endpoint, "mute").as((m) =>
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
    <box className="mixer-section" vertical spacing={4}>
      <label className="section-title" label="Output Volume" xalign={0} />
      <box className="volume-row" vertical={false} spacing={8}>
        <label
          className="volume-icon"
          label={bind(speaker, "volume").as((v) =>
            v === 0 ? "󰝟" : v < 0.33 ? "󰕿" : v < 0.66 ? "󰖀" : "󰕾"
          )}
        />
        <slider
          className="volume-slider"
          hexpand
          value={bind(speaker, "volume")}
          onDragged={(self) => {
            speaker.volume = self.value;
          }}
        />
        <label
          className="volume-percent"
          label={bind(speaker, "volume").as((v) =>
            `${Math.round(v * 100)}%`
          )}
          widthRequest={48}
        />
        <button
          className={bind(speaker, "mute").as((m) =>
            m ? "mute-btn muted" : "mute-btn"
          )}
          onClicked={() => {
            speaker.mute = !speaker.mute;
          }}
        >
          <label
            label={bind(speaker, "mute").as((m) =>
              m ? "󰖁" : "󰕾"
            )}
          />
        </button>
      </box>
    </box>
  );
}

function AppStreams() {
  const streams = bind(audio, "streams");

  return (
    <box className="mixer-section" vertical spacing={4}>
      <label className="section-title" label="Applications" xalign={0} />
      {streams.as((list) => {
        if (list.length === 0) {
          return (
            <label
              className="no-streams"
              label="No audio applications running"
              xalign={0}
            />
          );
        }
        return list.map((stream) => (
          <VolumeSlider
            endpoint={stream}
            label={bind(stream, "description").as((d) => d ?? "Unknown")}
          />
        ));
      })}
    </box>
  );
}

function OutputDevices() {
  const speakers = bind(audio, "speakers");
  const defaultSpeaker = audio.defaultSpeaker;

  return (
    <box className="mixer-section device-list" vertical spacing={4}>
      <label className="section-title" label="Output Devices" xalign={0} />
      {speakers.as((list) =>
        list.map((device) => (
          <button
            className={bind(defaultSpeaker, "id").as((id) =>
              device.id === id ? "device-item active" : "device-item"
            )}
            onClicked={() => {
              device.set_is_default(true);
            }}
          >
            <box spacing={8}>
              <label className="device-icon" label="󰓃" />
              <label
                className="device-name"
                label={bind(device, "description").as((d) => d ?? "Unknown")}
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
    <box className="mixer-section" vertical spacing={4}>
      <label className="section-title" label="Input" xalign={0} />
      <box className="volume-row" vertical={false} spacing={8}>
        <label
          className="volume-icon"
          label={bind(mic, "mute").as((m) => (m ? "󰍭" : "󰍬"))}
        />
        <slider
          className="volume-slider"
          hexpand
          value={bind(mic, "volume")}
          onDragged={(self) => {
            mic.volume = self.value;
          }}
        />
        <label
          className="volume-percent"
          label={bind(mic, "volume").as((v) =>
            `${Math.round(v * 100)}%`
          )}
          widthRequest={48}
        />
        <button
          className={bind(mic, "mute").as((m) =>
            m ? "mute-btn muted" : "mute-btn"
          )}
          onClicked={() => {
            mic.mute = !mic.mute;
          }}
        >
          <label
            label={bind(mic, "mute").as((m) =>
              m ? "󰍭" : "󰍬"
            )}
          />
        </button>
      </box>
      <box className="device-list" vertical spacing={2}>
        {bind(audio, "microphones").as((list) =>
          list.map((device) => (
            <button
              className={bind(mic, "id").as((id) =>
                device.id === id ? "device-item active" : "device-item"
              )}
              onClicked={() => {
                device.set_is_default(true);
              }}
            >
              <box spacing={8}>
                <label className="device-icon" label="󰍬" />
                <label
                  className="device-name"
                  label={bind(device, "description").as(
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
      className="audiomixer-popup"
      layer={Astal.Layer.OVERLAY}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT}
      visible={false}
      keymode={Astal.Keymode.ON_DEMAND}
      margin_top={8}
      margin_right={8}
      setup={(self) => registerPopup("audiomixer", self)}
      onKeyPressEvent={(self, event) => {
        if (event.get_keyval()[1] === Gdk.KEY_Escape) {
          self.visible = false;
        }
      }}
    >
      <box className="audiomixer-content" vertical spacing={12}>
        <MasterSection />
        <AppStreams />
        <OutputDevices />
        <InputSection />
      </box>
    </window>
  );
}

export default AudioMixer;
