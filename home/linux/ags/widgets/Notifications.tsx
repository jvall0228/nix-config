import { Astal, Gtk, Gdk } from "ags/gtk3";
import { createBinding, createState } from "ags";
import { timeout } from "ags/time";
import Notifd from "gi://AstalNotifd";
import { registerPopup } from "../lib/popups";

const [dndMode, setDndMode] = createState(false);

function timeAgo(unixTime: number): string {
  const seconds = Math.floor(Date.now() / 1000) - unixTime;
  if (seconds < 60) return "Just now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return `${Math.floor(seconds / 86400)}d ago`;
}

function urgencyClass(n: Notifd.Notification): string {
  switch (n.urgency) {
    case Notifd.Urgency.CRITICAL:
      return "urgency-critical";
    case Notifd.Urgency.LOW:
      return "urgency-low";
    default:
      return "";
  }
}

function NotificationIcon({ notification: n }: { notification: Notifd.Notification }) {
  if (n.appIcon) {
    return <icon icon={n.appIcon} />;
  }
  return <icon icon="dialog-information-symbolic" />;
}

function ActionButtons({ notification: n }: { notification: Notifd.Notification }) {
  if (!n.actions || n.actions.length === 0) return <box />;

  return (
    <box class="notification-actions" spacing={4}>
      {n.actions.map((action) => (
        <button
          class="notification-action-btn"
          onClick={() => n.invoke(action.id)}
          hexpand
        >
          <label label={action.label} />
        </button>
      ))}
    </box>
  );
}

function NotificationCard({
  notification: n,
  showTime,
  onDismiss,
}: {
  notification: Notifd.Notification;
  showTime?: boolean;
  onDismiss?: () => void;
}) {
  return (
    <button
      class={`notification-card ${urgencyClass(n)}`}
      onClick={() => {
        if (onDismiss) onDismiss();
        n.dismiss();
      }}
    >
      <box vertical spacing={4}>
        <box spacing={8}>
          <NotificationIcon notification={n} />
          <box vertical hexpand>
            <box spacing={4}>
              <label
                class="notification-app-name"
                label={n.appName || "Notification"}
                halign={Gtk.Align.START}
              />
              {showTime && (
                <label
                  class="notification-time"
                  label={timeAgo(n.time)}
                  hexpand
                  halign={Gtk.Align.END}
                />
              )}
            </box>
            <label
              class="notification-summary"
              label={n.summary}
              halign={Gtk.Align.START}
              wrap
              maxWidthChars={40}
            />
            {n.body && (
              <label
                class="notification-body"
                label={n.body}
                halign={Gtk.Align.START}
                wrap
                maxWidthChars={40}
              />
            )}
          </box>
        </box>
        <ActionButtons notification={n} />
      </box>
    </button>
  );
}

function NotificationPopups() {
  const notifd = Notifd.get_default();
  const [popupIds, setPopupIds] = createState<number[]>([]);

  function addPopup(id: number) {
    const n = notifd.get_notification(id);
    if (!n) return;

    if (dndMode.peek()) return;

    setPopupIds([id, ...popupIds.peek()].slice(0, 3));

    if (n.urgency !== Notifd.Urgency.CRITICAL) {
      timeout(5000, () => {
        removePopup(id);
      });
    }
  }

  function removePopup(id: number) {
    setPopupIds(popupIds.peek().filter((i) => i !== id));
  }

  notifd.connect("notified", (_, id) => addPopup(id));
  notifd.connect("resolved", (_, id) => removePopup(id));

  return (
    <window
      name="notification-popups"
      class="notification-popup"
      layer={Astal.Layer.OVERLAY}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.RIGHT}
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={popupIds.as((ids) => ids.length > 0)}
    >
      <box vertical spacing={8} class="notification-popup-list">
        {popupIds.as((ids) =>
          ids.map((id) => {
            const n = notifd.get_notification(id);
            if (!n) return <box />;
            return (
              <NotificationCard
                notification={n}
                onDismiss={() => removePopup(id)}
              />
            );
          }),
        )}
      </box>
    </window>
  );
}

function NotificationCenter() {
  const notifd = Notifd.get_default();

  return (
    <window
      name="notifications"
      layer={Astal.Layer.OVERLAY}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT}
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={false}
      keymode={Astal.Keymode.EXCLUSIVE}
      $={(self) => registerPopup("notifications", self)}
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
        <box hexpand vexpand halign={Gtk.Align.END} valign={Gtk.Align.FILL}>
          <eventbox onClick={() => true}>
            <box class="notification-center" vertical spacing={8}>
              <box class="notification-center-header" spacing={8}>
                <label
                  label="Notifications"
                  class="notification-center-title"
                  hexpand
                  halign={Gtk.Align.START}
                />
                <button
                  class="notification-dnd-toggle"
                  onClick={() => setDndMode(!dndMode.peek())}
                >
                  <label label={dndMode.as((d) => d ? "DND On" : "DND Off")} />
                </button>
                <button
                  class="notification-clear-btn"
                  onClick={() => {
                    notifd.notifications.forEach((n) => n.dismiss());
                  }}
                >
                  <label label="Clear All" />
                </button>
              </box>

              <scrollable
                class="notification-center-scroll"
                vexpand
                hscrollbarPolicy={Gtk.PolicyType.NEVER}
                vscrollbarPolicy={Gtk.PolicyType.AUTOMATIC}
              >
                <box vertical spacing={4}>
                  {createBinding(notifd, "notifications").as((notifications) => {
                    if (notifications.length === 0) {
                      return (
                        <label
                          class="notification-empty"
                          label="No notifications"
                          vexpand
                          valign={Gtk.Align.CENTER}
                          halign={Gtk.Align.CENTER}
                        />
                      );
                    }
                    return [...notifications]
                      .reverse()
                      .map((n) => (
                        <NotificationCard notification={n} showTime />
                      ));
                  })}
                </box>
              </scrollable>
            </box>
          </eventbox>
        </box>
      </eventbox>
    </window>
  );
}

export default function Notifications() {
  return [NotificationPopups(), NotificationCenter()];
}
