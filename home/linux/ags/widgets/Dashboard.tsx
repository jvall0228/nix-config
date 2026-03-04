import { Astal, Gtk, Gdk } from "ags/gtk3";
import { createBinding, createState, type Accessor } from "ags";
import { createPoll } from "ags/time";
import { registerPopup } from "../lib/popups";
import { sh, shSync } from "../lib/utils";

// Polling variables for system stats
const cpuUsage = createPoll("0", 3000, ["sh", "-c", "top -bn1 | grep 'Cpu(s)' | awk '{print $2}'"]);
const ramUsage = createPoll("0", 3000, ["sh", "-c", "free | awk '/Mem:/ {printf \"%.0f\", $3/$2*100}'"]);
const gpuUsage = createPoll("0", 5000, ["sh", "-c", "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo 0"]);
const diskUsage = createPoll("0", 60000, ["sh", "-c", "df / | awk 'NR==2 {print $5}' | tr -d '%'"]);
const cpuTemp = createPoll("0", 3000, ["sh", "-c", "cat /sys/class/hwmon/hwmon3/temp1_input | awk '{printf \"%.0f\", $1/1000}'"]);
const gpuTemp = createPoll("0", 5000, ["sh", "-c", "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null || echo 0"]);
const uptime = createPoll("", 60000, ["sh", "-c", "uptime -p | sed 's/up //'"]);
const [hostname] = createState(shSync("hostname"));
const [username] = createState(shSync("whoami"));

// Quick settings state
const [dndEnabled, setDndEnabled] = createState(false);
const [wifiEnabled, setWifiEnabled] = createState(shSync("nmcli radio wifi").trim() === "enabled");
const [btEnabled, setBtEnabled] = createState(shSync("bluetoothctl show | grep 'Powered:' | awk '{print $2}'").trim() === "yes");
const [nightLightOn, setNightLightOn] = createState(shSync("pgrep wlsunset > /dev/null && echo 1 || echo 0").trim() === "1");
const [idleInhibited, setIdleInhibited] = createState(shSync("systemctl --user is-active hypridle.service 2>/dev/null").trim() !== "active");
const [screenRecording, setScreenRecording] = createState(false);
let screenRecPid: string | null = null;

// Battery polling
const batteryPercent = createPoll("0", 10000, ["sh", "-c", "cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 0"]);
const batteryStatus = createPoll("Unknown", 10000, ["sh", "-c", "cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo 'Unknown'"]);

function ProfileCard() {
  return (
    <box class="profile-card" vertical spacing={4}>
      <box spacing={12}>
        <icon icon="avatar-default-symbolic" css="font-size: 48px;" />
        <box vertical valign={Gtk.Align.CENTER}>
          <label
            class="profile-username"
            label={username}
            halign={Gtk.Align.START}
          />
          <label
            class="profile-hostname"
            label={hostname.as((h) => `@${h}`)}
            halign={Gtk.Align.START}
          />
          <label
            class="profile-uptime"
            label={uptime.as((u) => `up ${u}`)}
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
  active: Accessor<boolean>;
  onToggle: () => void;
}) {
  return (
    <button
      class={active.as((a) => `toggle-btn ${a ? "active" : ""}`)}
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
    <box class="quick-settings" vertical spacing={8}>
      <label label="Quick Settings" halign={Gtk.Align.START} class="section-title" />
      <box homogeneous spacing={8}>
        <ToggleButton
          icon="network-wireless-symbolic"
          label="WiFi"
          active={wifiEnabled}
          onToggle={() => {
            const next = !wifiEnabled.peek();
            sh(`nmcli radio wifi ${next ? "on" : "off"}`);
            setWifiEnabled(next);
          }}
        />
        <ToggleButton
          icon="bluetooth-symbolic"
          label="BT"
          active={btEnabled}
          onToggle={() => {
            const next = !btEnabled.peek();
            sh(`bluetoothctl power ${next ? "on" : "off"}`);
            setBtEnabled(next);
          }}
        />
        <ToggleButton
          icon="notifications-disabled-symbolic"
          label="DND"
          active={dndEnabled}
          onToggle={() => {
            setDndEnabled(!dndEnabled.peek());
          }}
        />
      </box>
      <box homogeneous spacing={8}>
        <ToggleButton
          icon="night-light-symbolic"
          label="Night Light"
          active={nightLightOn}
          onToggle={() => {
            if (nightLightOn.peek()) {
              sh("pkill wlsunset");
            } else {
              sh("wlsunset -t 4000 -T 6500");
            }
            setNightLightOn(!nightLightOn.peek());
          }}
        />
        <ToggleButton
          icon="system-lock-screen-symbolic"
          label="Idle"
          active={idleInhibited}
          onToggle={() => {
            if (idleInhibited.peek()) {
              sh("systemctl --user start hypridle.service");
            } else {
              sh("systemctl --user stop hypridle.service");
            }
            setIdleInhibited(!idleInhibited.peek());
          }}
        />
        <ToggleButton
          icon="media-record-symbolic"
          label="Screen Rec"
          active={screenRecording}
          onToggle={() => {
            if (screenRecording.peek() && screenRecPid) {
              sh(`kill ${screenRecPid}`);
              screenRecPid = null;
              setScreenRecording(false);
            } else {
              sh("wl-screenrec -f /tmp/recording.mp4 & echo $!").then((pid) => {
                screenRecPid = pid.trim();
                setScreenRecording(true);
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
  value: Accessor<string>;
  suffix?: string;
}) {
  return (
    <box spacing={8}>
      <label label={labelText} widthChars={5} halign={Gtk.Align.START} />
      <levelbar
        class="stat-bar"
        hexpand
        maxValue={100}
        value={value.as((v) => parseFloat(v) || 0)}
      />
      <label
        label={value.as((v) => `${v}${suffix || "%"}`)}
        widthChars={6}
        halign={Gtk.Align.END}
      />
    </box>
  );
}

function SystemStats() {
  return (
    <box class="system-stats" vertical spacing={8}>
      <label label="System" halign={Gtk.Align.START} class="section-title" />
      <StatBar label="CPU" value={cpuUsage} />
      <StatBar label="RAM" value={ramUsage} />
      <StatBar label="GPU" value={gpuUsage} />
      <StatBar label="Disk" value={diskUsage} />
      <box class="temps" spacing={16}>
        <label
          label={cpuTemp.as((t) => `CPU: ${t}°C`)}
          halign={Gtk.Align.START}
          hexpand
        />
        <label
          label={gpuTemp.as((t) => `GPU: ${t}°C`)}
          halign={Gtk.Align.END}
          hexpand
        />
      </box>
    </box>
  );
}

function PowerSection() {
  return (
    <box class="power-section" vertical spacing={8}>
      <label label="Power" halign={Gtk.Align.START} class="section-title" />
      <box spacing={8}>
        <icon
          icon={batteryStatus.as((s) =>
            s.trim() === "Charging"
              ? "battery-caution-charging-symbolic"
              : "battery-symbolic",
          )}
        />
        <label
          label={batteryPercent.as((p) => `${p}%`)}
          halign={Gtk.Align.START}
        />
        <label
          label={batteryStatus.as((s) => s.trim())}
          halign={Gtk.Align.END}
          hexpand
        />
      </box>
      <levelbar
        class="battery-bar"
        maxValue={100}
        value={batteryPercent.as((p) => parseFloat(p) || 0)}
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
    <box class="session-actions" homogeneous spacing={8}>
      {actions.map((action) => (
        <button
          class="session-btn"
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
      layer={Astal.Layer.OVERLAY}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT}
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={false}
      keymode={Astal.Keymode.EXCLUSIVE}
      $={(self) => {
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
      <eventbox
        hexpand
        vexpand
        onClick={(self) => { self.get_toplevel().visible = false; }}
      >
        <box hexpand vexpand halign={Gtk.Align.START} valign={Gtk.Align.START}>
          <eventbox onClick={() => true}>
            <box class="dashboard-popup" vertical spacing={12}>
              <ProfileCard />
              <QuickSettings />
              <SystemStats />
              <PowerSection />
              <SessionActions dashboard={windowRef!} />
            </box>
          </eventbox>
        </box>
      </eventbox>
    </window>
  );
}

export default Dashboard;
