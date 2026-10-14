# Current build validation

Isolated package, configuration, startup simulation, ownership, recovery and removal-boundary tests passed as part of Build-Release.ps1.

Fresh Windows 11 VM installation, video import/switch/visible preview, complete uninstall and normal post-uninstall startup: **passed for this exact build**. Login animation playback before uninstall was not separately observed for this build. Windows 10 real-machine testing: **not completed**. Do not carry forward a previous build's success without rerunning the integration cycle.

## 2026-10-14: read-only import fix

Current installer: v0.25 / 0.2.5.3. SHA-256: DCC1691AA4C948EDC30F40BDBA1CBEFF9B5F5D0113D5528D46D83C95A4CA2142.

Prior 0.2.5.2 build installed and configured successfully on the clean Windows 11 VM; ISO video import and automatic switching worked. User confirmed normal login animation. Actual uninstall then failed safely before startup restoration/deletion: FileAccess.ReadWrite preflight could not open the read-only video copy imported from the ISO. Preserved offline diagnostic snapshot: 2026-10-14_v025-readonly-uninstall-failure.

0.2.5.3 removes the read-only attribute only from newly imported managed copies; source attributes remain unchanged. Removal preflight uses exclusive read access instead of requiring write access. Isolated checks passed for read-only source import, read-only media cleanup, genuine media locks and removal boundaries. Fresh snapshot install/import/uninstall retest passed; the old build's playback result is not a full-cycle pass for this build.

## Current build actual VM checks (2026-10-14)

- Restored clean Windows 11 Enterprise LTSC 2024 VM, 4 GB; agent installed exact 0.2.5.3 release ISO with default startup and shortcut options. Installer showed startup configuration success.
- App launched, generated sample frame visible; same read-only ISO Test-Switch.mp4 imported and automatically applied, 8 seconds / 1280x720, frame visible.
- Closed app through taskbar Close Window. Windows Installed Apps showed Boot Studio v0.25 (Test), version 0.2.5.3.
- Actual uninstall through Installed Apps completed. Completion dialog states original startup restored, files/config/logs/imported copies/shortcuts deleted. Boot Studio disappeared from Installed Apps and desktop shortcut disappeared. Success is emitted only after independent startup Status checks Enabled=false and Recovery=false and complete directory removal verification.
- Post-uninstall cold startup reached Windows lock screen. User logged in and confirmed normal desktop startup. Agent then observed the working desktop with no Boot Studio shortcut. No snapshot restore or reinstallation occurred between uninstall and this verification.
- Agent independently browsed %LOCALAPPDATA% with hidden items shown: seven entries, no BootStudio directory. Local\Temp contained only Low, cv_debug, msedge_installer and wmsetup; no BootStudio installer/uninstaller staging directory remained. This corroborates removal of the program, managed media, configuration, logs and temporary staging files.
- VirtualBox initially failed before guest startup with host process error 5 while MessageTransfer was running. At the user's explicit authorization, an elevated helper temporarily stopped only MessageTransfer; StartMode stayed Auto. The same VM then started successfully. This host-side launch issue is separate from guest uninstall verification; host Boot Studio startup configuration was not changed.
- Current build login playback was not separately observed before this uninstall; earlier user-confirmed playback was for 0.2.5.2. Latest build is still an unsigned test release, not a complete Windows 10/11 compatibility certification.

## User follow-up (2026-10-14)

The user reported successful 0.2.5.3 testing after restoring the clean VM snapshot, and later reported successful testing on their own Windows PC. These are user observations; no additional logs or repeated reboot counts were collected for those runs. Windows 10 remains untested.

