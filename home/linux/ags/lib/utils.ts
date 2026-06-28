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
  // exec() throws on a non-zero exit. shSync is used at module-load time for
  // state probes (e.g. `systemctl is-active hypridle`, which exits 3 when the
  // unit is stopped), so a throw here crashes the ENTIRE shell into a restart
  // loop. Fail soft: return best-effort output instead of throwing. Callers
  // .trim()/compare the result, so an empty string degrades gracefully.
  try {
    return exec(["sh", "-c", cmd]);
  } catch (e) {
    return typeof e === "string" ? e : String((e as any)?.stdout ?? "");
  }
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
