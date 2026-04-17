import pyttsx3

tts = pyttsx3.init()
tts.say("Привет! Если ты слышишь это, значит озвучка работает.")
tts.runAndWait()
