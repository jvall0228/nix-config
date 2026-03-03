import { App, Astal, Gtk, Gdk } from "astal/gtk3";
import { bind, Variable, interval } from "astal";
import { registerPopup } from "../lib/popups";
import { sh, shSync, readFile } from "../lib/utils";

// Polling variables for system stats
const cpuUsage = Variable("0").poll(3000, ["sh", "-c", "top -bn1 | grep 'Cpu(s)' | awk '{print $2}'"]);
const ramUsage = Variable("0").poll(3000, ["sh", "-c", "free | awk '/Mem:/ {printf \"%.0f\", $3/$2*100}'"]);
const gpuUsage = Variable("0").poll(5000, ["sh", "-c", "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo 0"]);
const diskUsage = Variable("0").poll(60000, ["sh", "-c", "df / | awk 'NR==2 {print $5}' | tr -d '%'"]);
const cpuTemp = Variable("0").poll(3000, ["sh", "-c", "cat /sys/class/hwmon/hwmon3/temp1_input | awk '{printf \"%.0f\", $1/1000}'"]);
const gpuTemp = Variable("0").poll(5000, ["sh", "-c", "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo 0"]);
const uptime = Variable("").poll(60000, ["sh", "-c", "uptime -p | sed 's/up //'"]);
const hostname = Variable(shSync("hostname"));
const username = Variable(shSync("whoami"));

// Quick settings state
const dndEnabled = Variable(false);
const wifiEnabled = Variable(shSync("nmcli radio wifi").trim() === "enabled");
const btEnabled = Variable(shSync("bluetoothctl show | grep 'Powered:' | awk '{print $2}'").trim() === "yes");
const nightLightOn = Variable(shSync("pgrep wlsunset > /dev/null && echo 1 || echo 0").trim() === "1");
const idleInhibited = Variable(shSync("systemctl --user is-active hypridle.service 2>/dev/null").trim() !== "active");
const screenRecording = Variable(false);
let screenRecPid: string | null = null;

// Battery polling
const batteryPercent = Variable("0").poll(10000, ["sh", "-c", "cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 0"]);
const batteryStatus = Variable("Unknown").poll(10000, ["sh", "-c", "cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo 'Unknown'"]);

function ProfileCard() {
  return (
    <box className="profile-card" vertical spacing={4}>
      <box spacing={12}>
        <icon icon="avatar-default-symbolic" css="font-size: 48px;" />
        <box vertical valign={Gtk.Align.CENTER}>
          <label
            className="profile-username"
            label={bind(username)}
            halign={Gtk.Align.START}
          />
          <label
            className="profile-hostname"
            label={bind(hostname).as((h) => `@${h}`)}
            halign={Gtk.Align.START}
          />
          <label
            className="profile-uptime"
            label={bind(uptime).as((u) => `up ${u}`)}
            halign={Gtk.Align.START}
          />
        </box>
      </box>
    </box>
  );
}

function ToggleButton({
  icon: iconName,
  label: labelText,
  active,
  onToggle,
}: {
  icon: string;
  label: string;
  active: Variable<boolean>;
  onToggle: () => void;
}) {
  return (
    <button
      className={bind(active).as((a) => `toggle-btn ${a ? "active" : ""}`)}
      onClick={onToggle}
    >
      <box vertical spacing={4} halign={Gtk.Align.CENTER}>
        <icon icon={iconName} />
        <label label={labelText} />
      </box>
    </button>
  );
}

function QuickSettings() {
  return (
    <box className="quick-settings" vertical spacing={8}>
      <label label="Quick Settings" halign={Gtk.Align.START} className="section-title" />
      <box homogeneous spacing={8}>
        <ToggleButton
          icon="network-wireless-symbolic"
          label="WiFi"
          active={wifiEnabled}
          onToggle={() => {
            const next = !wifiEnabled.get();
            sh(`nmcli radio wifi ${next ? "on" : "off"}`);
            wifiEnabled.set(next);
          }}
        />
        <ToggleButton
          icon="bluetooth-symbolic"
          label="BT"
          active={btEnabled}
          onToggle={() => {
            const next = !btEnabled.get();
            sh(`bluetoothctl power ${next ? "on" : "off"}`);
            btEnabled.set(next);
          }}
        />
        <ToggleButton
          icon="notifications-disabled-symbolic"
          label="DND"
          active={dndEnabled}
          onToggle={() => {
            dndEnabled.set(!dndEnabled.get());
          }}
        />
      </box>
      <box homogeneous spacing={8}>
        <ToggleButton
          icon="night-light-symbolic"
          label="Night Light"
          active={nightLightOn}
          onToggle={() => {
            if (nightLightOn.get()) {
              sh("pkill wlsunset");
            } else {
              sh("wlsunset -t 4000 -T 6500");
            }
            nightLightOn.set(!nightLightOn.get());
          }}
        />
        <ToggleButton
          icon="system-lock-screen-symbolic"
          label="Idle"
          active={idleInhibited}
          onToggle={() => {
            if (idleInhibited.get()) {
              sh("systemctl --user start hypridle.service");
            } else {
              sh("systemctl --user stop hypridle.service");
            }
            idleInhibited.set(!idleInhibited.get());
          }}
        />
        <ToggleButton
          icon="media-record-symbolic"
          label="Screen Rec"
          active={screenRecording}
          onToggle={() => {
            if (screenRecording.get() && screenRecPid) {
              sh(`kill ${screenRecPid}`);
              screenRecPid = null;
              screenRecording.set(false);
            } else {
              sh("wl-screenrec -f /tmp/recording.mp4 & echo $!").then((pid) => {
                screenRecPid = pid.trim();
                screenRecording.set(true);
              });
            }
          }}
        />
      </box>
    </box>
  );
}

function StatBar({
  label: labelText,
  value,
  suffix,
}: {
  label: string;
  value: Variable<string>;
  suffix?: string;
}) {
  return (
    <box spacing={8}>
      <label label={labelText} widthChars={5} halign={Gtk.Align.START} />
      <levelbar
        className="stat-bar"
        hexpand
        maxValue={100}
        value={bind(value).as((v) => parseFloat(v) || 0)}
      />
      <label
        label={bind(value).as((v) => `${v}${suffix || "%"}`)}
        widthChars={6}
        halign={Gtk.Align.END}
      />
    </box>
  );
}

function SystemStats() {
  return (
    <box className="system-stats" vertical spacing={8}>
      <label label="System" halign={Gtk.Align.START} className="section-title" />
      <StatBar label="CPU" value={cpuUsage} />
      <StatBar label="RAM" value={ramUsage} />
      <StatBar label="GPU" value={gpuUsage} />
      <StatBar label="Disk" value={diskUsage} />
      <box className="temps" spacing={16}>
        <label
          label={bind(cpuTemp).as((t) => `CPU: ${t}°C`)}
          halign={Gtk.Align.START}
          hexpand
        />
        <label
          label={bind(gpuTemp).as((t) => `GPU: ${t}°C`)}
          halign={Gtk.Align.END}
          hexpand
        />
      </box>
    </box>
  );
}

function PowerSection() {
  return (
    <box className="power-section" vertical spacing={8}>
      <label label="Power" halign={Gtk.Align.START} className="section-title" />
      <box spacing={8}>
        <icon
          icon={bind(batteryStatus).as((s) =>
            s.trim() === "Charging"
              ? "battery-caution-charging-symbolic"
              : "battery-symbolic",
          )}
        />
        <label
          label={bind(batteryPercent).as((p) => `${p}%`)}
          halign={Gtk.Align.START}
        />
        <label
          label={bind(batteryStatus).as((s) => s.trim())}
          halign={Gtk.Align.END}
          hexpand
        />
      </box>
      <levelbar
        className="battery-bar"
        maxValue={100}
        value={bind(batteryPercent).as((p) => parseFloat(p) || 0)}
      />
    </box>
  );
}

function SessionActions({ dashboard }: { dashboard: Gtk.Window }) {
  const actions = [
    { icon: "system-lock-screen-symbolic", label: "Lock", cmd: "hyprlock" },
    { icon: "system-log-out-symbolic", label: "Logout", cmd: "hyprctl dispatch exit" },
    { icon: "media-playback-pause-symbolic", label: "Suspend", cmd: "systemctl suspend" },
    { icon: "system-reboot-symbolic", label: "Reboot", cmd: "systemctl reboot" },
    { icon: "system-shutdown-symbolic", label: "Shutdown", cmd: "systemctl poweroff" },
  ];

  return (
    <box className="session-actions" homogeneous spacing={8}>
      {actions.map((action) => (
        <button
          className="session-btn"
          tooltipText={action.label}
          onClick={() => {
            dashboard.visible = false;
            sh(action.cmd);
          }}
        >
          <box vertical spacing={4} halign={Gtk.Align.CENTER}>
            <icon icon={action.icon} />
            <label label={action.label} />
          </box>
        </button>
      ))}
    </box>
  );
}

function Dashboard() {
  let windowRef: Gtk.Window;

  return (
    <window
      name="dashboard"
      className="dashboard-popup"
      layer={Astal.Layer.OVERLAY}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.LEFT}
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={false}
      keymode={Astal.Keymode.ON_DEMAND}
      setup={(self) => {
        windowRef = self;
        registerPopup("dashboard", self);
      }}
      onKeyPressEvent={(self, event) => {
        const [, keyval] = event.get_keyval();
        if (keyval === Gdk.KEY_Escape) {
          self.visible = false;
        }
      }}
    >
      <box className="dashboard-container" vertical spacing={12}>
        <ProfileCard />
        <QuickSettings />
        <SystemStats />
        <PowerSection />
        <SessionActions dashboard={windowRef!} />
      </box>
    </window>
  );
}

export default Dashboard;
