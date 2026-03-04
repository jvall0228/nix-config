import { Astal, Gtk, Gdk } from "ags/gtk3";
import { createBinding } from "ags";
import Network from "gi://AstalNetwork";
import { registerPopup } from "../lib/popups";
import { sh } from "../lib/utils";

function signalIcon(strength: number): string {
  if (strength >= 75) return "󰤨";
  if (strength >= 50) return "󰤥";
  if (strength >= 25) return "󰤢";
  return "󰤟";
}

function WifiToggle({ wifi }: { wifi: Network.Wifi }) {
  return (
    <box class="wifi-toggle" spacing={8}>
      <label label="WiFi" hexpand halign={Gtk.Align.START} />
      <switch
        active={createBinding(wifi, "enabled")}
        onActivate={({ active }) => {
          wifi.enabled = active;
        }}
      />
    </box>
  );
}

function ConnectedInfo({ wifi }: { wifi: Network.Wifi }) {
  return (
    <box class="connected-info" spacing={8} visible={createBinding(wifi, "ssid").as((s) => !!s)}>
      <label
        class="signal-icon"
        label={createBinding(wifi, "strength").as(signalIcon)}
      />
      <label
        class="connected-ssid"
        label={createBinding(wifi, "ssid").as((s) => s ?? "Not connected")}
        hexpand
        halign={Gtk.Align.START}
      />
      <label class="connected-badge" label="Connected" />
    </box>
  );
}

function AccessPointEntry({
  ap,
  currentSsid,
}: {
  ap: Network.AccessPoint;
  currentSsid: string | null;
}) {
  const ssid = ap.ssid ?? "";
  const isConnected = ssid === currentSsid;

  return (
    <button
      class={`network-entry ${isConnected ? "active" : ""}`}
      onClick={() => {
        if (!isConnected && ssid) {
          sh(`nmcli device wifi connect "${ssid}"`);
        }
      }}
    >
      <box spacing={8}>
        <label class="signal-icon" label={signalIcon(ap.strength)} />
        <label label={ssid || "Hidden Network"} hexpand halign={Gtk.Align.START} />
        {isConnected && <label class="connected-badge" label="✓" />}
      </box>
    </button>
  );
}

function WifiList({ wifi }: { wifi: Network.Wifi }) {
  return (
    <box class="network-list" vertical>
      {createBinding(wifi, "accessPoints").as((aps) => {
        const currentSsid = wifi.ssid;
        const seen = new Set<string>();

        return aps
          .filter((ap) => {
            const ssid = ap.ssid;
            if (!ssid || seen.has(ssid)) return false;
            seen.add(ssid);
            return true;
          })
          .sort((a, b) => b.strength - a.strength)
          .map((ap) => (
            <AccessPointEntry ap={ap} currentSsid={currentSsid} />
          ));
      })}
    </box>
  );
}

function EthernetStatus({ wired }: { wired: Network.Wired | null }) {
  if (!wired) return <box />;

  return (
    <box class="ethernet-status" spacing={8}>
      <label class="signal-icon" label="󰈀" />
      <label label="Ethernet" hexpand halign={Gtk.Align.START} />
      <label
        label={createBinding(wired, "speed").as((s) => (s > 0 ? `${s} Mbps` : "Disconnected"))}
      />
    </box>
  );
}

function NetworkMenu() {
  const network = Network.get_default();
  const wifi = network.wifi;
  const wired = network.wired;

  return (
    <window
      name="network"
      class="network-popup"
      layer={Astal.Layer.OVERLAY}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT}
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={false}
      keymode={Astal.Keymode.ON_DEMAND}
      setup={(self) => registerPopup("network", self)}
      onKeyPressEvent={(self, event) => {
        const [, keyval] = event.get_keyval();
        if (keyval === Gdk.KEY_Escape) {
          self.visible = false;
        }
      }}
    >
      <box class="network-container" vertical spacing={4}>
        {wifi && <WifiToggle wifi={wifi} />}
        {wifi && <ConnectedInfo wifi={wifi} />}
        {wifi && (
          <scrollable
            class="network-scroll"
            vexpand
            hscrollbarPolicy={Gtk.PolicyType.NEVER}
            vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC}
            heightRequest={300}
          >
            <WifiList wifi={wifi} />
          </scrollable>
        )}
        <EthernetStatus wired={wired} />
      </box>
    </window>
  );
}

export default NetworkMenu;
