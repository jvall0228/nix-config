import GLib from "gi://GLib";
import { exec, execAsync } from "ags/process";

export function getFocusedMonitor(): number {
  try {
    const result = exec("hyprctl monitors -j");
    const monitors = JSON.parse(result);
    const focused = monitors.find((m: any) => m.focused);
    return focused?.id ?? 0;
  } catch {
    return 0;
  }
}

export function sh(cmd: string): Promise<string> {
  return execAsync(["sh", "-c", cmd]);
}

export function shSync(cmd: string): string {
  return exec(["sh", "-c", cmd]);
}

export function readFile(path: string): string {
  try {
    const [ok, contents] = GLib.file_get_contents(path);
    if (ok) {
      const decoder = new TextDecoder();
      return decoder.decode(contents).trim();
    }
  } catch { }
  return "";
}
