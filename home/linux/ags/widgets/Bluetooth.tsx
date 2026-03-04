import { Astal, Gtk, Gdk } from "ags/gtk3";
import { createBinding } from "ags";
import Bluetooth from "gi://AstalBluetooth";
import { registerPopup } from "../lib/popups";

function DeviceItem({ device }: { device: Bluetooth.Device }) {
  const connected = createBinding(device, "connected");
  const name = createBinding(device, "name");
  const battery = createBinding(device, "batteryPercentage");
  const icon = createBinding(device, "icon");

  return (
    <button
      class={connected.as((c) => `device-item ${c ? "connected" : ""}`)}
      onClick={() => {
        if (device.connected) {
          device.disconnect_device();
        } else {
          device.connect_device();
        }
      }}
    >
      <box spacing={8}>
        <icon icon={icon.as((i) => i || "bluetooth-symbolic")} />
        <label label={name.as((n) => n || "Unknown")} hexpand halign={Gtk.Align.START} />
        {battery.as((b) =>
          b >= 0 ? (
            <label class="device-battery" label={`${b}%`} />
          ) : (
            <box />
          ),
        )}
        <icon
          icon={connected.as((c) =>
            c ? "network-wireless-connected-symbolic" : "network-wireless-offline-symbolic",
          )}
        />
      </box>
    </button>
  );
}

function BluetoothMenu() {
  const bt = Bluetooth.get_default();

  return (
    <window
      name="bluetooth"
      layer={Astal.Layer.OVERLAY}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT}
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={false}
      keymode={Astal.Keymode.EXCLUSIVE}
      $={(self) => registerPopup("bluetooth", self)}
      onKeyPressEvent={(self, event) => {
        const [, keyval] = event.get_keyval();
        if (keyval === Gdk.KEY_Escape) {
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
            <box class="bluetooth-popup" vertical spacing={8}>
              <box class="bluetooth-header" spacing={8}>
                <label label="Bluetooth" hexpand halign={Gtk.Align.START} />
                <switch
                  class="bt-toggle"
                  active={createBinding(bt, "isPowered")}
                  onActivate={({ active }) => {
                    bt.adapter.powered = active;
                  }}
                />
              </box>

              <box class="device-list" vertical spacing={4}>
                {createBinding(bt, "devices").as((devices) =>
                  devices
                    .filter((d) => d.paired)
                    .map((device) => <DeviceItem device={device} />),
                )}
              </box>

              <button
                class="scan-btn"
                onClick={() => {
                  bt.adapter.start_discovery();
                }}
              >
                <box spacing={8} halign={Gtk.Align.CENTER}>
                  <icon icon="system-search-symbolic" />
                  <label label="Scan" />
                </box>
              </button>
            </box>
          </eventbox>
        </box>
      </eventbox>
    </window>
  );
}

export default BluetoothMenu;
