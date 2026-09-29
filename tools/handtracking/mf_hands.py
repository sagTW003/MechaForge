"""mf_hands.py — Captura y seguimiento de manos para el Laboratorio matemático de MechaForge.

Capa «HandTracker» (captura + inferencia) del sistema de seguimiento de manos:

  cámara ──(hilo de captura: solo el último fotograma)──► MediaPipe HandLandmarker
         ──► UDP 127.0.0.1:<puerto> (JSON con token) ──► HandTracker.gd (Godot)

- Corre en un proceso aparte: la inferencia nunca bloquea el render de Godot.
- El hilo de captura descarta los fotogramas viejos (búfer de 1), así la latencia
  es la de un solo fotograma más la inferencia (~6–11 ms en CPU).
- La imagen se voltea (vista de espejo): «Left» es la mano izquierda del usuario.
- Solo envía a 127.0.0.1 y cada paquete lleva el token que le pasa MechaForge.
  No guarda ni envía imágenes: solo las coordenadas de los 21 puntos de cada mano.
- Termina solo si MechaForge se cierra (vigila el PID del proceso padre).

Uso (lo lanza MechaForge; a mano, para diagnosticar):
  python mf_hands.py --port 18791 --token XXXX [--camera -1] [--width 640 --height 480 --fps 60]
  python mf_hands.py --selftest --port 18791 --token XXXX   (sin cámara: modelo + UDP)
"""

import argparse
import json
import os
import socket
import sys
import threading
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_MODEL = os.path.join(SCRIPT_DIR, "models", "hand_landmarker.task")


class Sender:
    """Envía paquetes JSON por UDP solo a la interfaz local."""

    def __init__(self, port, token):
        self.addr = ("127.0.0.1", port)
        self.token = token
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.seq = 0

    def send(self, payload):
        self.seq += 1
        payload["token"] = self.token
        payload["seq"] = self.seq
        try:
            self.sock.sendto(json.dumps(payload, separators=(",", ":")).encode("utf-8"), self.addr)
        except OSError:
            pass

    def status(self, msg, level="info", **extra):
        d = {"type": "status", "level": level, "msg": msg}
        d.update(extra)
        self.send(d)


def log(msg):
    print("[mf_hands] " + msg, flush=True)


def parent_alive(pid):
    """¿Sigue vivo el proceso padre? (sin os.kill, que en Windows lo mataría)."""
    if pid <= 0:
        return True
    if os.name == "nt":
        import ctypes
        synchronize = 0x00100000
        h = ctypes.windll.kernel32.OpenProcess(synchronize, False, pid)
        if not h:
            return False
        try:
            return ctypes.windll.kernel32.WaitForSingleObject(h, 0) == 0x102  # WAIT_TIMEOUT
        finally:
            ctypes.windll.kernel32.CloseHandle(h)
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def start_watchdog(pid, stop):
    def run():
        while not stop.is_set():
            if not parent_alive(pid):
                log("MechaForge se ha cerrado: termino.")
                stop.set()
                return
            time.sleep(1.0)
    threading.Thread(target=run, daemon=True).start()


def make_landmarker(model_path, max_hands):
    import mediapipe as mp  # noqa: F401  (comprueba que está instalado)
    from mediapipe.tasks import python as mpp
    from mediapipe.tasks.python import vision
    opts = vision.HandLandmarkerOptions(
        base_options=mpp.BaseOptions(model_asset_path=model_path),
        running_mode=vision.RunningMode.VIDEO,
        num_hands=max_hands,
        min_hand_detection_confidence=0.6,
        min_hand_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    return vision.HandLandmarker.create_from_options(opts)


def pack_result(result):
    hands = []
    for i, lms in enumerate(result.hand_landmarks):
        cat = result.handedness[i][0] if i < len(result.handedness) and result.handedness[i] else None
        wl = result.hand_world_landmarks[i] if i < len(result.hand_world_landmarks) else []
        hands.append({
            "label": cat.category_name if cat else "Right",
            "score": round(float(cat.score), 3) if cat else 0.0,
            "lm": [[round(p.x, 5), round(p.y, 5), round(p.z, 5)] for p in lms],
            "wlm": [[round(p.x, 5), round(p.y, 5), round(p.z, 5)] for p in wl],
        })
    return hands


class Capture:
    """Hilo de captura que conserva solo el fotograma más reciente."""

    def __init__(self, cap):
        self.cap = cap
        self.lock = threading.Lock()
        self.frame = None
        self.t = 0.0
        self.fresh = False
        self.failures = 0
        self.stop = threading.Event()
        threading.Thread(target=self._run, daemon=True).start()

    def _run(self):
        while not self.stop.is_set():
            ok, frame = self.cap.read()
            if not ok:
                self.failures += 1
                time.sleep(0.01)
                continue
            self.failures = 0
            with self.lock:
                self.frame = frame
                self.t = time.time()
                self.fresh = True

    def latest(self):
        with self.lock:
            if not self.fresh:
                return None, 0.0
            self.fresh = False
            return self.frame, self.t


def open_camera(index, width, height, fps):
    import cv2
    indices = [index] if index >= 0 else [0, 1, 2, 3]
    backends = [("DSHOW", cv2.CAP_DSHOW), ("MSMF", cv2.CAP_MSMF)] if os.name == "nt" else [("ANY", cv2.CAP_ANY)]
    tried = []
    for i in indices:
        for name, be in backends:
            cap = cv2.VideoCapture(i, be)
            tried.append("%d/%s" % (i, name))
            if cap.isOpened():
                cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
                cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
                cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
                cap.set(cv2.CAP_PROP_FPS, fps)
                cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
                ok, _ = cap.read()
                if ok:
                    return cap, "%d/%s" % (i, name), tried
            cap.release()
    return None, "", tried


def run_camera(args, sender, stop):
    import cv2
    import mediapipe as mp
    landmarker = make_landmarker(args.model, args.max_hands)
    cap, where, tried = open_camera(args.camera, args.width, args.height, args.fps)
    if cap is None:
        sender.status("No se pudo abrir ninguna cámara (probé %s). Revisa Configuración > Privacidad > Cámara "
                      "y cierra otras aplicaciones que la usen (p. ej. el HUD Viernes)." % ", ".join(tried), "error")
        return 2
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    cam_fps = cap.get(cv2.CAP_PROP_FPS)
    sender.status("Cámara %s abierta: %dx%d a %.0f fps." % (where, w, h, cam_fps), "ok", width=w, height=h, cam_fps=cam_fps)
    log("cámara %s %dx%d %.0f fps" % (where, w, h, cam_fps))
    grab = Capture(cap)
    last_ts = 0
    last_status = time.time()
    frames = 0
    while not stop.is_set():
        frame, t_cap = grab.latest()
        if frame is None:
            if grab.failures > 120:
                sender.status("La cámara dejó de enviar imágenes.", "error")
                break
            time.sleep(0.001)
            continue
        frame = cv2.flip(frame, 1)
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        ts = max(last_ts + 1, int(time.perf_counter() * 1000))
        last_ts = ts
        t0 = time.perf_counter()
        result = landmarker.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), ts)
        inf_ms = (time.perf_counter() - t0) * 1000.0
        sender.send({"type": "hands", "t_cap": t_cap, "t_send": time.time(), "inf_ms": round(inf_ms, 2),
                     "w": w, "h": h, "hands": pack_result(result)})
        frames += 1
        if time.time() - last_status > 5.0:
            last_status = time.time()
            log("%d fotogramas, inferencia %.1f ms" % (frames, inf_ms))
    grab.stop.set()
    cap.release()
    landmarker.close()
    return 0


def synthetic_point(t):
    """Mano derecha sintética «apuntando» que describe un círculo (para la autoprueba)."""
    import math
    cx = 0.5 + 0.15 * math.cos(t)
    cy = 0.5 + 0.1 * math.sin(t)
    # Puntos en coordenadas de imagen (x, y en [0, 1]) y de mundo (metros).
    base = [(0, 0.09), (-0.03, 0.07), (-0.05, 0.05), (-0.055, 0.03), (-0.05, 0.015),
            (-0.02, 0.0), (-0.02, -0.04), (-0.02, -0.065), (-0.02, -0.085),
            (0.0, 0.0), (0.0, 0.02), (0.0, 0.035), (0.0, 0.025),
            (0.02, 0.005), (0.02, 0.025), (0.02, 0.035), (0.02, 0.028),
            (0.035, 0.012), (0.035, 0.028), (0.035, 0.036), (0.035, 0.03)]
    lm = [[round(cx + x * 2.0, 5), round(cy + y * 2.0, 5), 0.0] for x, y in base]
    wlm = [[x, y, 0.0] for x, y in base]
    return [{"label": "Right", "score": 0.99, "lm": lm, "wlm": wlm}]


def run_selftest(args, sender):
    """Sin cámara: comprueba el modelo, mide la inferencia y prueba el canal UDP."""
    import numpy as np
    import mediapipe as mp
    landmarker = make_landmarker(args.model, args.max_hands)
    img = np.zeros((480, 640, 3), np.uint8)
    ts = 0
    times = []
    for i in range(25):
        ts += 16
        t0 = time.perf_counter()
        landmarker.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=img), ts)
        times.append((time.perf_counter() - t0) * 1000.0)
    inf = sorted(times[5:])[len(times[5:]) // 2]
    landmarker.close()
    sender.status("Autoprueba: modelo cargado, inferencia %.1f ms." % inf, "ok", selftest=True, inf_ms=round(inf, 2))
    for k in range(40):
        sender.send({"type": "hands", "t_cap": time.time(), "t_send": time.time(), "inf_ms": round(inf, 2),
                     "w": 640, "h": 480, "hands": synthetic_point(k * 0.15)})
        time.sleep(1.0 / 60.0)
    sender.status("Autoprueba terminada.", "ok", selftest_done=True)
    return 0


def main():
    ap = argparse.ArgumentParser(description="Seguimiento de manos de MechaForge (MediaPipe → UDP local).")
    ap.add_argument("--port", type=int, default=18791)
    ap.add_argument("--token", default="")
    ap.add_argument("--camera", type=int, default=-1, help="índice de la cámara (-1 = probar 0..3)")
    ap.add_argument("--width", type=int, default=640)
    ap.add_argument("--height", type=int, default=480)
    ap.add_argument("--fps", type=int, default=60)
    ap.add_argument("--max-hands", type=int, default=2)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--parent-pid", type=int, default=0)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    sender = Sender(args.port, args.token)
    stop = threading.Event()
    start_watchdog(args.parent_pid, stop)
    if not os.path.isfile(args.model):
        sender.status("No encuentro el modelo %s." % args.model, "error")
        return 3
    try:
        import cv2  # noqa: F401
        import mediapipe  # noqa: F401
    except ImportError as e:
        sender.status("Falta un paquete de Python (%s). Instala: pip install -r requirements.txt" % e.name, "error")
        return 4
    sender.status("Cargando MediaPipe…", "info")
    try:
        return run_selftest(args, sender) if args.selftest else run_camera(args, sender, stop)
    except Exception as e:  # informa a MechaForge en lugar de morir en silencio
        sender.status("Error en el seguimiento: %s: %s" % (type(e).__name__, e), "error")
        log("error: %r" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
