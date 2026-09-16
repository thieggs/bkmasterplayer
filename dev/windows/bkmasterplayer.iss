; Instalador do BKmasterplayer para Windows.
;
; Gera um .exe único que instala o app, cria os atalhos e registra o
; AppUserModelID -- sem ele o Windows não junta as notificações do app
; com o ícone dele na barra de tarefas, e o toast de troca de música
; aparece sem nome.
;
; Uso (na máquina Windows, depois de `flutter build windows --release`):
;   iscc /DVersao=1.0.0 dev\windows\bkmasterplayer.iss

#define Nome "BKmasterplayer"
#define Publicador "thieggs"
#define AppId "io.github.playermusica.player_musica"
#define Executavel "player_musica.exe"
#ifndef Versao
  #define Versao "1.0.0"
#endif
#ifndef Bundle
  #define Bundle "..\..\app\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{8F3C1A42-6D5E-4B7A-9E21-BK4D5A5C5539}
AppName={#Nome}
AppVersion={#Versao}
AppVerName={#Nome} {#Versao}
AppPublisher={#Publicador}
DefaultDirName={autopf}\{#Nome}
DefaultGroupName={#Nome}
; Instala só para quem está usando: não pede administrador.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\dist
OutputBaseFilename={#Nome}-{#Versao}-instalador
SetupIconFile=..\..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#Executavel}
UninstallDisplayName={#Nome}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; O motor de áudio é x64.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
LicenseFile=..\..\LICENSE

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "{cm:AutoStartProgram,{#Nome}}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#Bundle}\{#Executavel}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Bundle}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Bundle}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; O AppUserModelID precisa estar no atalho, e ser o mesmo que o app usa:
; é assim que o Windows liga a notificação ao programa.
Name: "{group}\{#Nome}"; Filename: "{app}\{#Executavel}"; AppUserModelID: "{#AppId}"
Name: "{group}\{cm:UninstallProgram,{#Nome}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#Nome}"; Filename: "{app}\{#Executavel}"; AppUserModelID: "{#AppId}"; Tasks: desktopicon
Name: "{userstartup}\{#Nome}"; Filename: "{app}\{#Executavel}"; AppUserModelID: "{#AppId}"; Tasks: startup

[Run]
Filename: "{app}\{#Executavel}"; Description: "{cm:LaunchProgram,{#Nome}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Cache de música e capas; as preferências ficam, para reinstalar não perder a conta.
Type: filesandordirs; Name: "{localappdata}\{#AppId}\cache"
