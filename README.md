# WhatsMissing

WhatsMissing is a launcher that provides some extensions to the official Windows WhatsApp client.

<p align="center">
  <img src="./.github/WhatsApp.png" alt="WhatsApp">
</p>
<p align="center">
  <img src="./.github/Settings.png" alt="Settings">
</p>
<p align="center">
  <img src="./.github/Notification.png" alt="Notification icon">
</p>

### Features
- Some of WhatsApp's colors can be changed
- WhatsApp can be minimized to the notification area using the close button/escape key
- Notification icon indicates whether new messages were received
- WhatsApp can be configured to be always on top
- Suppression of outbound online/typing notifications
- Suppression of consecutive notification sounds
- Easy installation/uninstallation without modifications to WhatsApp's original files
- Built using Lazarus :fire:

### Requirements
- [WhatsApp client](https://www.whatsapp.com/download) (64 and 32 Bit supported)

### Installation
Download the installer from "Releases" and run it. WhatsMissing will install itself to %LOCALAPPDATA%\WhatsMissing, configuration will be saved to %APPDATA%\WhatsMissing after first start.

WhatsApp shortcuts in the start menu/taskbar/desktop are modified by the installer to start the WhatsMissing executable which in turn starts WhatsApp with the extensions.

Complete uninstallation is possible using "Programs and Features".

### How to use
When WhatsApp is running right click the notification icon to open the settings dialog or toggle "Always on top". The menu entries displayed in the notification icon context menu are also accessible using the title bar context menu.

### Building
- Install Lazarus IDE and the tools to crosscompile
- Install MSYS2 with mingw32 (only required for building the installer)

To use the build script "Build.bat" you need to configure variables at the top of the file.

### Thanks
- [Lazarus IDE](https://www.lazarus-ide.org)
- [Free Pascal](https://www.freepascal.org)
- [Font Awesome](https://fontawesome.com) for application icon
- [Yusuke Kamiyamane](https://p.yusukekamiyamane.com/about) for Fugue Icons
- [MahdiSafsafi](https://github.com/MahdiSafsafi) for DDetours and ImmersiveColors
- [Alex Ionescu](https://github.com/ionescu007) for minlzma
