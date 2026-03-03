import { App, Astal, Gtk, Gdk } from "astal/gtk3";
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
      className="calendar-popup"
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
      <box className="calendar-container" vertical>
        <box className="calendar-nav" homogeneous>
          <button
            className="calendar-nav-btn"
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
            className="calendar-nav-btn"
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
            className="calendar-nav-btn"
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
