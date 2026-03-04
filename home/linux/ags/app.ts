import app from "ags/gtk3/app";
import GLib from "gi://GLib";

import { togglePopup } from "./lib/popups";
import Calendar from "./widgets/Calendar";
import AudioMixer from "./widgets/AudioMixer";
import NetworkMenu from "./widgets/Network";
import BluetoothMenu from "./widgets/Bluetooth";
import MediaPlayer from "./widgets/Media";
import Dashboard from "./widgets/Dashboard";
import Notifications from "./widgets/Notifications";
import OSD, { showOSD } from "./widgets/OSD";

const configDir = `${GLib.get_user_config_dir()}/ags`;

app.start({
  css: `${configDir}/style.css`,
  main() {
    Calendar();
    AudioMixer();
    NetworkMenu();
    BluetoothMenu();
    MediaPlayer();
    Dashboard();
    Notifications();
    OSD();
  },

  requestHandler(argv: string[], response: (msg: string) => void) {
    const [action, target, ...rest] = argv;

    switch (action) {
      case "toggle":
        if (target) {
          togglePopup(target);
          response(`toggled ${target}`);
        } else {
          response("error: missing widget name");
        }
        break;

      case "osd":
        if (target) {
          showOSD(target);
          response(`osd ${target}`);
        } else {
          response("error: missing osd type");
        }
        break;

      default:
        response(`unknown command: ${action}`);
    }
  },
});
