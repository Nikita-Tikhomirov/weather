# Android Call QA

Use this flow to verify incoming audio/video call behavior without waiting for FCM.

Prerequisites:
- Install the latest release APK.
- Open the app once after install.
- In Profile -> System calls, make the row show the enabled/check state.
  If it asks for setup, enable the Android phone account, app notifications,
  and full-screen alerts when Android opens the related settings.
- Connect the phone with USB debugging enabled.

Windows adb path used on the development machine:

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
```

Lock the phone, then trigger an audio call:

```powershell
& $adb shell input keyevent KEYCODE_SLEEP
& $adb shell am broadcast `
  -a com.example.family_todo_mobile.action.TEST_INCOMING_CALL `
  -n com.example.family_todo_mobile/.IncomingCallTestReceiver `
  --es call_type audio `
  --es session_id qa_audio_001 `
  --es caller_display_name "QA Audio Call"
```

Lock the phone, then trigger a video call:

```powershell
& $adb shell input keyevent KEYCODE_SLEEP
& $adb shell am broadcast `
  -a com.example.family_todo_mobile.action.TEST_INCOMING_CALL `
  -n com.example.family_todo_mobile/.IncomingCallTestReceiver `
  --es call_type video `
  --es session_id qa_video_001 `
  --es caller_display_name "QA Video Call"
```

Expected result:
- The phone wakes from the lock screen.
- A ringtone/vibration starts according to the device sound mode.
- The incoming call is shown as a call surface, not as an ordinary push card.
- Accept opens the in-app call screen; decline stops ringtone/vibration and closes the incoming call surface.

If the result is still an ordinary notification:
- Open Profile -> System calls and confirm there is a check mark.
- Re-run the same `adb shell am broadcast ...` command while the phone is locked.
- Capture diagnostics with:

```powershell
& $adb shell dumpsys notification --noredact | findstr /i "family_todo family_calls fullscreen"
& $adb shell dumpsys telecom | findstr /i "Family Todo family_todo"
```

The QA receiver is protected with `android.permission.DUMP`, so normal apps cannot trigger it. It is intended for `adb shell` verification only.
