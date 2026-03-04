import { Gtk } from "ags/gtk3";

const popups = new Map<string, Gtk.Window>();

export function registerPopup(name: string, window: Gtk.Window) {
  popups.set(name, window);
}

export function closeAllPopups(except?: string) {
  for (const [key, win] of popups) {
    if (key !== except) {
      win.visible = false;
    }
  }
}

export function togglePopup(name: string) {
  closeAllPopups(name);
  const target = popups.get(name);
  if (target) {
    target.visible = !target.visible;
  }
}

export function isPopupVisible(name: string): boolean {
  return popups.get(name)?.visible ?? false;
}
