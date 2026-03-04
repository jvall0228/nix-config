import { App, Astal, Gtk, Gdk } from "astal/gtk3";
import { bind } from "astal";
import Bluetooth from "gi://AstalBluetooth";
import { registerPopup } from "../lib/popups";

function DeviceItem({ device }: { device: Bluetooth.Device }) {
  const connected = bind(device, "connected");
  const name = bind(device, "name");
  const battery = bind(device, "batteryPercentage");
  const icon = bind(device, "icon");

  return (
    <button
      className={connected.as((c) => `device-item ${c ? "connected" : ""}`)}
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
            <label className="device-battery" label={`${b}%`} />
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
      className="bluetooth-popup"
      layer={Astal.Layer.OVERLAY}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT}
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={false}
      keymode={Astal.Keymode.ON_DEMAND}
      setup={(self) => registerPopup("bluetooth", self)}
      onKeyPressEvent={(self, event) => {
        const [, keyval] = event.get_keyval();
        if (keyval === Gdk.KEY_Escape) {
          self.visible = false;
        }
      }}
    >
      <box className="bluetooth-container" vertical spacing={8}>
        <box className="bluetooth-header" spacing={8}>
          <label label="Bluetooth" hexpand halign={Gtk.Align.START} />
          <switch
            className="bt-toggle"
            active={bind(bt, "isPowered")}
            onActivate={({ active }) => {
              bt.adapter.powered = active;
            }}
          />
        </box>

        <box className="device-list" vertical spacing={4}>
          {bind(bt, "devices").as((devices) =>
            devices
              .filter((d) => d.paired)
              .map((device) => <DeviceItem device={device} />),
          )}
        </box>

        <button
          className="scan-btn"
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
    </window>
  );
}

export default BluetoothMenu;
