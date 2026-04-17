import os
import tempfile
import time

import speech_recognition as sr

from config import SETTINGS
from todo_logger import log_event, log_exception

try:
    import winsound
except Exception:  # pragma: no cover
    winsound = None


recognizer = sr.Recognizer()
recognizer.dynamic_energy_threshold = True
recognizer.energy_threshold = 80
recognizer.pause_threshold = 1.4
recognizer.non_speaking_duration = 0.6
recognizer.phrase_threshold = 0.15
recognizer.dynamic_energy_adjustment_damping = 0.1
recognizer.dynamic_energy_ratio = 1.25

_WHISPER_MODEL = None
_WHISPER_INIT_DONE = False
_STT_REPLACEMENTS = {
    "аришу": "ариша",
    "крысу": "крыс",
    "туду": "тудушка",
}


def _play_listen_cue() -> None:
    """Play a short pleasant cue right before microphone starts listening."""
    if not winsound:
        return
    try:
        winsound.PlaySound("SystemAsterisk", winsound.SND_ALIAS | winsound.SND_ASYNC)
    except Exception:
        try:
            winsound.MessageBeep(winsound.MB_OK)
        except Exception:
            pass


def _language_short(language: str) -> str:
    # e.g. ru-RU -> ru
    return (language or "ru").split("-")[0].lower()


def _init_faster_whisper():
    global _WHISPER_MODEL, _WHISPER_INIT_DONE
    if _WHISPER_INIT_DONE:
        return _WHISPER_MODEL

    _WHISPER_INIT_DONE = True
    try:
        from faster_whisper import WhisperModel

        model_name = os.getenv("FW_MODEL", "large-v3")
        device = os.getenv("FW_DEVICE", "cpu")
        compute_type_default = "float16" if device.lower() == "cuda" else "int8_float16"
        compute_type = os.getenv("FW_COMPUTE_TYPE", compute_type_default)
        _WHISPER_MODEL = WhisperModel(model_name, device=device, compute_type=compute_type)
        print(f"faster-whisper loaded: model={model_name}, device={device}, compute={compute_type}")
    except Exception as exc:
        _WHISPER_MODEL = None
        print(f"faster-whisper unavailable, fallback to Google STT: {exc}")
        log_exception("stt_whisper_init_failed", exc)

    return _WHISPER_MODEL


def _recognize_whisper(audio: sr.AudioData, language: str) -> str:
    model = _init_faster_whisper()
    if model is None:
        return ""

    temp_path = None
    try:
        wav_bytes = audio.get_wav_data(convert_rate=16000, convert_width=2)
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as f:
            temp_path = f.name
            f.write(wav_bytes)

        segments, _info = model.transcribe(
            temp_path,
            language=_language_short(language),
            beam_size=int(os.getenv("FW_BEAM_SIZE", "5")),
            best_of=int(os.getenv("FW_BEST_OF", "5")),
            vad_filter=True,
            temperature=0,
            condition_on_previous_text=False,
        )
        text = " ".join(seg.text for seg in segments).strip().lower()
        return text
    except Exception as exc:
        log_exception("stt_whisper_transcribe_failed", exc)
        return ""
    finally:
        if temp_path and os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except OSError:
                pass


def _recognize_google_best(audio: sr.AudioData, language: str) -> str:
    """Try n-best recognition first, then fall back to a plain transcript."""
    try:
        result = recognizer.recognize_google(audio, language=language, show_all=True)
        if isinstance(result, dict):
            alternatives = result.get("alternative", [])
            for alt in alternatives:
                transcript = alt.get("transcript", "").strip().lower()
                if transcript:
                    return transcript
    except sr.UnknownValueError:
        return ""
    except sr.RequestError:
        return ""
    except Exception:
        pass

    try:
        return recognizer.recognize_google(audio, language=language).lower().strip()
    except (sr.UnknownValueError, sr.RequestError):
        return ""
    except Exception:
        return ""


def _recognize_best(audio: sr.AudioData, language: str) -> str:
    # Prefer local faster-whisper; fallback to Google STT.
    text = _recognize_whisper(audio, language)
    if text:
        out = _postprocess_transcript(text)
        if out:
            log_event("stt_recognized", engine="whisper")
        return out
    out = _postprocess_transcript(_recognize_google_best(audio, language))
    if out:
        log_event("stt_recognized", engine="google")
    return out


def _postprocess_transcript(text: str) -> str:
    normalized = (text or "").strip().lower()
    if not normalized:
        return ""
    for src, dst in _STT_REPLACEMENTS.items():
        normalized = normalized.replace(src, dst)
    if os.getenv("STT_DEBUG", "0") == "1":
        print(f"STT => {normalized}")
    return normalized


def listen_speech(
    timeout: int = SETTINGS.audio.default_timeout,
    phrase_time_limit: int = SETTINGS.audio.default_phrase_time_limit,
    ambient_duration: float = SETTINGS.audio.default_ambient_duration,
    language: str = SETTINGS.audio.language,
    retries: int = 1,
    with_cue: bool = True,
) -> str:
    """Listen from microphone and return recognized text."""
    calibrated = False

    for attempt in range(retries + 1):
        if with_cue and attempt == 0:
            _play_listen_cue()
            time.sleep(0.18)

        with sr.Microphone() as source:
            if ambient_duration > 0 and not calibrated:
                recognizer.adjust_for_ambient_noise(source, duration=ambient_duration)
                calibrated = True

            try:
                audio = recognizer.listen(
                    source,
                    timeout=timeout,
                    phrase_time_limit=phrase_time_limit,
                )
            except sr.WaitTimeoutError:
                continue

        text = _recognize_best(audio, language)
        if text:
            return text

    return ""


def listen_command(
    timeout: int = SETTINGS.audio.default_timeout,
    phrase_time_limit: int = SETTINGS.audio.default_phrase_time_limit,
    ambient_duration: float = SETTINGS.audio.default_ambient_duration,
    language: str = SETTINGS.audio.language,
) -> str:
    """Listen from microphone and return a normalized command string."""
    print("Ожидаю голосовую команду...")
    command = listen_speech(
        timeout=timeout,
        phrase_time_limit=phrase_time_limit,
        ambient_duration=ambient_duration,
        language=language,
        retries=1,
        with_cue=False,
    )
    if command:
        print(f"Распознано: {command}")
        return command

    print("Не удалось распознать речь.")
    return ""
