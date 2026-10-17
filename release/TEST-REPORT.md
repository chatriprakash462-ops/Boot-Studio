# Boot Studio 0.2.5.5 — bundled Shinjuku video

Test date: 2026-10-17. Installer SHA-256: 7D3F793AD8B9B6344957A1043D1E882704E7F2D73CFC0FB06CF3C3EAACF80C21.

## Passed

- Final installer built and extracted into an isolated directory; all 24 payload file hashes matched. Default video is media/shinjuku-rain.mp4, with a generated sample.mp4 backup. The initial library has two entries with validated paths and hashes. MEDIA-NOTICE.txt is included in the installer and distribution files.
- The provider explicitly confirmed authorization to publicly distribute the video, visuals and music together with the application. Source attribution is included; the media is not presented as public domain or covered by the software's license.
- Original source retained unchanged. Distribution copy is H.264 at 1920x1080, 30 fps, about 110 seconds, 65,484,841 bytes. Complete FFmpeg decode passed. Original AAC audio stream was copied during encoding.
- Final application decoded the distribution video with Windows MediaPlayer and passed isolated import, duplicate detection, selected-video hash validation, exact configuration undo and corrupt-media rejection. Windows reported a 109-second duration for this file; container duration is approximately 109.97 seconds.
- Duration-cap tests and safety timing checks passed: 120 seconds accepted, longer/invalid durations rejected, 180-second launcher deadline and 210-second recovery schedule. Recovery, ownership, cancellation, lost-backup, read-only/locked media and removal-boundary regressions also passed.

## Pending / scope

No fresh VM installation, full visible 110-second login playback, reboot or actual uninstall of this exact installer was performed in this task. Windows 10 and additional computers/codecs remain untested. Prior build's successful real-machine update and reboot tests do not establish compatibility for this binary. This remains an unsigned test release.

The currently installed application and its selected video were not changed by this packaging task. Existing users should back up their videos/configuration and uninstall the old version before a clean install; this installer does not overwrite an existing installation.
