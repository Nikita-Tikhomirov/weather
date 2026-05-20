"""
Audio zones voice command handler.
Trigger: "зоны" — lists available audio zones and devices.
"""
import os
import sys

from audio_zones import list_output_devices, list_zones, play_tts


def main():
    # If called with text argument, try to parse a TTS command
    if len(sys.argv) > 1:
        full_text = " ".join(sys.argv[1:]).lower()
    else:
        full_text = ""

    if "скажи" in full_text or "произнеси" in full_text:
        # Try: скажи ПРИВЕТ в КУХНЕ
        zones_info = list_zones()
        zone_names = list(zones_info.keys())

        target_zone = "default"
        for zn in zone_names:
            if zn in full_text:
                target_zone = zn
                break

        # Extract text between "скажи/произнеси" and zone name
        import re
        words = full_text.split()
        try:
            say_idx = next(i for i, w in enumerate(words) if w in ("скажи", "произнеси"))
            text_words = words[say_idx + 1:]
            # Remove zone name from end
            if target_zone != "default" and target_zone in text_words:
                zn_idx = text_words.index(target_zone)
                text_words = text_words[:zn_idx]
            phrase = " ".join(text_words).strip()
        except (StopIteration, ValueError):
            phrase = ""

        if phrase:
            print(f"Озвучиваю: «{phrase}» в зоне «{target_zone}»")
            ok = play_tts(phrase, zone_name=target_zone)
            if ok:
                print("Готово.")
            else:
                print("Ошибка воспроизведения.")
        else:
            print("Не понял, что сказать. Пример: зоны скажи привет в кухне")
        return

    # Default: list zones
    devices = list_output_devices()
    zones = list_zones()

    print("=== Аудиозоны ===")
    for name, info in zones.items():
        marker = " ★" if name == "default" else ""
        print(f"  {name}{marker}: {info.get('device_name', '?')} (громкость: {info.get('volume', '?')}%)")

    print("\n=== Доступные устройства ===")
    for dev in devices:
        print(f"  [{dev['id']}] {dev['name']} ({dev['channels']}ch, {dev['hostapi']})")

    # Also speak a summary
    zone_list = ", ".join(
        f"{name} ({info.get('device_name', '?')})"
        for name, info in zones.items()
    )
    try:
        play_tts(f"Доступные зоны: {zone_list}", zone_name="default")
    except Exception:
        pass


if __name__ == "__main__":
    main()
