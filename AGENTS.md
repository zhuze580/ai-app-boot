# AI App Boot

This Windows project adds startup videos to **both Codex and Tencent WorkBuddy**. Read README.md before changes. WorkBuddy and Codex can both maintain the source project.

Run `npm test`. Run `npm run test:browser` on Windows with Microsoft Edge. Parse all PowerShell files with Windows PowerShell 5.1, and compile scripts/Native.cs with Accessibility, System and System.Core. There are no npm runtime dependencies.

Keep both completion conditions: play the whole video, and verify the actual target application's accessible editor and navigation before closing. If the video ends first, hold the last frame indefinitely. Esc/Skip remains available. Never resize the target application; only position the owned Chrome splash. Do not terminate Codex, WorkBuddy or user browser sessions. Do not modify installed application packages, themes or chat data.

Application discovery must use installed app evidence or an explicit local appPath; never commit machine-specific paths. DreamSkin is optional. Status files and Chrome profiles belong under LOCALAPPDATA/AIAppBoot. Do not read input values, document text, account URLs or credentials in readiness checks. Only accessible roles, states and known navigation labels are needed.

Do not commit config.local.json or runtime data. The user explicitly requests distributing assets/intro.mp4 as the default GitHub animation. It is user-supplied media with separate terms in assets/README.md, not MIT licensed. Runtime files and local development environments must stay outside releases.
