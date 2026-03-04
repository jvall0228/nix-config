import { Astal, Gtk, Gdk } from "ags/gtk3";
import { registerPopup } from "../lib/popups";

function Calendar() {
  const calendar = new Gtk.Calendar({
    visible: true,
    showDayNames: true,
    showHeading: true,
  });

  return (
    <window
      name="calendar"
      layer={Astal.Layer.OVERLAY}
      anchor={Astal.WindowAnchor.TOP | Astal.WindowAnchor.BOTTOM | Astal.WindowAnchor.LEFT | Astal.WindowAnchor.RIGHT}
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={false}
      keymode={Astal.Keymode.EXCLUSIVE}
      $={(self) => registerPopup("calendar", self)}
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
        <box hexpand vexpand halign={Gtk.Align.CENTER} valign={Gtk.Align.START}>
          <eventbox onClick={() => true}>
            <box class="calendar-popup" vertical>
              <box class="calendar-nav" homogeneous>
                <button
                  class="calendar-nav-btn"
                  onClick={() => {
                    const [year, month] = [
                      calendar.year,
                      calendar.month,
                    ];
                    if (month === 0) {
                      calendar.year = year - 1;
                      calendar.month = 11;
                    } else {
                      calendar.month = month - 1;
                    }
                  }}
                >
                  <label label="&#xf053;" />
                </button>
                <button
                  class="calendar-nav-btn"
                  onClick={() => {
                    const today = new Date();
                    calendar.year = today.getFullYear();
                    calendar.month = today.getMonth();
                    calendar.day = today.getDate();
                  }}
                >
                  <label label="Today" />
                </button>
                <button
                  class="calendar-nav-btn"
                  onClick={() => {
                    const [year, month] = [
                      calendar.year,
                      calendar.month,
                    ];
                    if (month === 11) {
                      calendar.year = year + 1;
                      calendar.month = 0;
                    } else {
                      calendar.month = month + 1;
                    }
                  }}
                >
                  <label label="&#xf054;" />
                </button>
              </box>
              {calendar}
            </box>
          </eventbox>
        </box>
      </eventbox>
    </window>
  );
}

export default Calendar;
