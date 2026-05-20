"""
Audio Zones — multi-room audio output management.

Enumerates output devices, assigns human-readable zone names,
and routes TTS/audio playback to specific zones through the bridge.
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
from pathlib import Path
from typing import Optional

import numpy as np
import sounddevice as sd

BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR / "family_data" / "audio_zones.json"
NIRCMD_PATH = BASE_DIR / "nircmd.exe"

DEFAULT_CONFIG: dict = {
    "zones": {
        "default": {"device_id": None, "volume": 70},
    }
}

_lock = threading.Lock()


# ═══════════════════════════════════════════════════════════════
# Config
# ═══════════════════════════════════════════════════════════════

def _load_config() -> dict:
    if CONFIG_PATH.exists():
        try:
            return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        except Exception:
            pass
    return json.loads(json.dumps(DEFAULT_CONFIG))


def _save_config(cfg: dict) -> None:
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(
        json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8"
    )


# ═══════════════════════════════════════════════════════════════
# Device enumeration
# ═══════════════════════════════════════════════════════════════

def list_output_devices() -> list[dict]:
    """Return list of output audio devices with id, name, channels."""
    devices: list[dict] = []
    for idx, dev in enumerate(sd.query_devices()):
        if dev.get("max_output_channels", 0) > 0:
            hostapi = sd.query_hostapis(dev["hostapi"])
            devices.append(
                {
                    "id": idx,
                    "name": dev["name"],
                    "channels": dev["max_output_channels"],
                    "default_samplerate": int(dev["default_samplerate"]),
                    "hostapi": hostapi["name"],
                }
            )
    return devices


def default_output_device_id() -> int | None:
    """Return the device id of the default output device, or None."""
    try:
        devices = sd.query_devices(kind="output")
        if isinstance(devices, dict):
            return devices.get("index")
        return None
    except Exception:
        return None


# ═══════════════════════════════════════════════════════════════
# Zone management
# ═══════════════════════════════════════════════════════════════

def list_zones() -> dict:
    """Return zone config merged with current device info."""
    cfg = _load_config()
    all_devices = {d["id"]: d for d in list_output_devices()}
    default_id = default_output_device_id()

    result: dict = {}
    for zone_name, zone_data in cfg.get("zones", {}).items():
        device_id = zone_data.get("device_id")
        if device_id is None:
            device_id = default_id
        device_info = (
            all_devices.get(device_id) if device_id is not None else None
        )
        result[zone_name] = {
            "name": zone_name,
            "device_id": device_id,
            "device_name": device_info["name"] if device_info else "auto",
            "volume": zone_data.get("volume", 70),
        }
    return result


def set_zone(
    zone_name: str,
    device_id: int | None = None,
    volume: int | None = None,
) -> dict:
    """Create or update a zone. Returns the zone dict."""
    cfg = _load_config()
    zones = cfg.setdefault("zones", {})
    if zone_name not in zones:
        zones[zone_name] = {
            "device_id": device_id,
            "volume": volume if volume is not None else 70,
        }
    else:
        if device_id is not None:
            zones[zone_name]["device_id"] = device_id
        if volume is not None:
            zones[zone_name]["volume"] = max(0, min(100, volume))
    _save_config(cfg)
    return list_zones().get(zone_name, {})


def remove_zone(zone_name: str) -> bool:
    """Remove a zone (except 'default')."""
    if zone_name == "default":
        return False
    cfg = _load_config()
    zones = cfg.get("zones", {})
    if zone_name in zones:
        del zones[zone_name]
        _save_config(cfg)
        return True
    return False


# ═══════════════════════════════════════════════════════════════
# Volume control
# ═══════════════════════════════════════════════════════════════

def get_volume(zone_name: str = "default") -> int:
    """Get configured volume for a zone (0-100)."""
    cfg = _load_config()
    zone = cfg.get("zones", {}).get(zone_name, {})
    return zone.get("volume", 70)


def set_volume(zone_name: str, volume: int) -> int:
    """Set configured volume for a zone (0-100), return new value."""
    v = max(0, min(100, volume))
    cfg = _load_config()
    cfg.setdefault("zones", {}).setdefault(zone_name, {})["volume"] = v
    _save_config(cfg)
    return v


def _set_system_volume(volume_pct: int) -> bool:
    """Set system master volume via nircmd (0-100 scaled to 0-65535)."""
    if not NIRCMD_PATH.exists():
        return False
    value = int(volume_pct / 100.0 * 65535)
    try:
        subprocess.run(
            [str(NIRCMD_PATH), "setsysvolume", str(value)],
            capture_output=True,
            timeout=4,
            check=False,
        )
        return True
    except Exception:
        return False


# ═══════════════════════════════════════════════════════════════
# Audio playback
# ═══════════════════════════════════════════════════════════════

def _play_array(
    samples: np.ndarray,
    samplerate: int,
    device_id: int | None = None,
    volume: int = 70,
) -> None:
    """Play a numpy audio array on a specific device at given volume."""
    adjusted = samples * (volume / 100.0)
    sd.play(adjusted, samplerate, device=device_id)
    sd.wait()


def play_tts(
    text: str, zone_name: str = "default", lang: str = "ru"
) -> bool:
    """Synthesize TTS and play to a specific zone."""
    text = (text or "").strip()
    if not text:
        return False

    zones = list_zones()
    zone = zones.get(zone_name, zones.get("default"))
    if not zone:
        return False

    device_id = zone.get("device_id")
    volume = zone.get("volume", 70)

    temp_path = None
    try:
        from gtts import gTTS
        from pydub import AudioSegment

        with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as f:
            temp_path = f.name

        tts = gTTS(text=text, lang=lang)
        tts.save(temp_path)
        audio = AudioSegment.from_mp3(temp_path)

        samples = np.array(audio.get_array_of_samples(), dtype=np.float32)
        if audio.channels == 1:
            samples /= 32768.0
        elif audio.channels == 2:
            samples = samples.reshape((-1, 2)) / 32768.0

        _play_array(samples, audio.frame_rate, device_id, volume)
        return True
    except Exception as exc:
        print(f"[audio_zones] TTS error: {exc}", flush=True)
        return False
    finally:
        if temp_path and os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except OSError:
                pass


def play_file(filepath: str, zone_name: str = "default") -> bool:
    """Play an audio file to a specific zone."""
    path = Path(filepath)
    if not path.exists():
        print(f"[audio_zones] File not found: {filepath}", flush=True)
        return False

    zones = list_zones()
    zone = zones.get(zone_name, zones.get("default"))
    if not zone:
        return False

    device_id = zone.get("device_id")
    volume = zone.get("volume", 70)

    try:
        from pydub import AudioSegment

        audio = AudioSegment.from_file(str(path))
        samples = np.array(audio.get_array_of_samples(), dtype=np.float32)
        if audio.channels == 1:
            samples /= 32768.0
        elif audio.channels == 2:
            samples = samples.reshape((-1, 2)) / 32768.0

        _play_array(samples, audio.frame_rate, device_id, volume)
        return True
    except Exception as exc:
        print(f"[audio_zones] play_file error: {exc}", flush=True)
        return False


def stop_playback() -> None:
    """Stop current audio playback."""
    try:
        sd.stop()
    except Exception:
        pass


# ═══════════════════════════════════════════════════════════════
# Bridge action dispatch — non-blocking via thread
# ═══════════════════════════════════════════════════════════════

def handle_bridge_action(action: dict) -> dict:
    """Process an audio_zones action from the bridge and return a result dict.

    Actions:
      - list_zones           → list all zones with device info
      - list_devices         → list raw output devices
      - set_zone             → {zone_name, device_id?, volume?}
      - remove_zone          → {zone_name}
      - play_tts             → {text, zone_name?, lang?}
      - play_file            → {filepath, zone_name?}
      - set_volume           → {zone_name, volume}
      - stop                 → stop playback
    """
    action_type = str(action.get("action") or "").strip()
    if not action_type:
        return {"error": "missing action"}

    if action_type == "list_zones":
        return {"zones": list_zones()}

    if action_type == "list_devices":
        return {"devices": list_output_devices()}

    if action_type == "set_zone":
        zone_name = str(action.get("zone_name") or "").strip()
        if not zone_name:
            return {"error": "missing zone_name"}
        device_id = action.get("device_id")
        volume = action.get("volume")
        zone = set_zone(zone_name, device_id, volume)
        return {"zone": zone}

    if action_type == "remove_zone":
        zone_name = str(action.get("zone_name") or "").strip()
        if not zone_name:
            return {"error": "missing zone_name"}
        ok = remove_zone(zone_name)
        return {"removed": ok}

    if action_type == "play_tts":
        text = str(action.get("text") or "").strip()
        if not text:
            return {"error": "missing text"}
        zone_name = str(action.get("zone_name") or "default").strip()
        lang = str(action.get("lang") or "ru").strip()
        # Run in thread so bridge stays responsive
        result_holder: dict = {"ok": False}

        def _run():
            result_holder["ok"] = play_tts(text, zone_name, lang)

        t = threading.Thread(target=_run, daemon=True)
        t.start()
        t.join(timeout=60)
        return {"played": result_holder["ok"], "zone": zone_name}

    if action_type == "play_file":
        filepath = str(action.get("filepath") or "").strip()
        if not filepath:
            return {"error": "missing filepath"}
        zone_name = str(action.get("zone_name") or "default").strip()
        result_holder: dict = {"ok": False}

        def _run():
            result_holder["ok"] = play_file(filepath, zone_name)

        t = threading.Thread(target=_run, daemon=True)
        t.start()
        t.join(timeout=120)
        return {"played": result_holder["ok"], "zone": zone_name}

    if action_type == "set_volume":
        zone_name = str(action.get("zone_name") or "default").strip()
        volume = action.get("volume")
        if volume is None:
            return {"error": "missing volume"}
        try:
            new_vol = set_volume(zone_name, int(volume))
            return {"volume": new_vol, "zone": zone_name}
        except (ValueError, TypeError):
            return {"error": "volume must be integer"}

    if action_type == "stop":
        stop_playback()
        return {"stopped": True}

    return {"error": f"unknown action: {action_type}"}
