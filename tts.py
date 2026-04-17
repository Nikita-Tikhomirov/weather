from contextlib import contextmanager
import os
import tempfile

from gtts import gTTS
from pydub import AudioSegment
from pydub.effects import speedup
from pydub.playback import play


VOICE_SPEED = 1.16
_MUTE_DEPTH = 0


@contextmanager
def muted_tts():
    global _MUTE_DEPTH
    _MUTE_DEPTH += 1
    try:
        yield
    finally:
        _MUTE_DEPTH = max(0, _MUTE_DEPTH - 1)


def speak(text: str, lang: str = "ru") -> None:
    """Synthesize text with gTTS and play a slightly faster audio."""
    try:
        from notifier import emit_assistant_message

        emit_assistant_message(text)
    except Exception:
        pass

    if _MUTE_DEPTH > 0:
        return

    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as temp_file:
            temp_path = temp_file.name

        tts = gTTS(text=text, lang=lang)
        tts.save(temp_path)
        audio = AudioSegment.from_mp3(temp_path)

        if len(audio) > 500:
            audio = speedup(audio, playback_speed=VOICE_SPEED, chunk_size=120, crossfade=20)

        play(audio)
    except Exception as exc:
        print(f"Ошибка озвучивания: {exc}")
    finally:
        if temp_path and os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except OSError:
                pass
