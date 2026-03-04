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
      class="calendar-popup"
      layer={Astal.Layer.OVERLAY}
      anchor={Astal.WindowAnchor.TOP}
      exclusivity={Astal.Exclusivity.IGNORE}
      visible={false}
      keymode={Astal.Keymode.ON_DEMAND}
      setup={(self) => registerPopup("calendar", self)}
      onKeyPressEvent={(self, event) => {
        const [, keyval] = event.get_keyval();
        if (keyval === Gdk.KEY_Escape) {
          self.visible = false;
        }
      }}
    >
      <box class="calendar-container" vertical>
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
    </window>
  );
}

export default Calendar;
