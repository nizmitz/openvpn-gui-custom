; Inno Setup script: bundles the official OpenVPN MSI and overlays the custom GUI.
; Build: ISCC.exe /DAppVersion=<ver> /DOpenVpnMsi=<path> /DBinDir=<dir> setup.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef OpenVpnMsi
  #define OpenVpnMsi "openvpn.msi"
#endif
#ifndef BinDir
  #define BinDir "."
#endif

[Setup]
AppId={{7B9C2E1A-3F44-4D6E-9A21-0C5E8F1D2B77}
AppName=OpenVPN Add-On for Password Protection
AppVersion={#AppVersion}
UninstallDisplayName=OpenVPN Add-On for Password Protection
UninstallDisplayIcon={app}\bin\openvpn-gui.exe
AppPublisher=nizmitz
VersionInfoProductName=OpenVPN Add-On for Password Protection
VersionInfoDescription=OpenVPN GUI without password reveal
AppPublisherURL=https://github.com/nizmitz/openvpn-gui-custom
DefaultDirName={commonpf64}\OpenVPN
DisableDirPage=yes
DisableProgramGroupPage=yes
CreateUninstallRegKey=yes
Uninstallable=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
CloseApplications=yes
RestartApplications=no
OutputBaseFilename=OpenVPN-PasswordProtection-AddOn-{#AppVersion}-setup
OutputDir=.
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Files]
; Official OpenVPN installer, only run when OpenVPN is not already present
Source: "{#OpenVpnMsi}"; DestName: "openvpn.msi"; Flags: dontcopy
; Custom GUI overlay -- never removed on uninstall, OpenVPN owns these paths
Source: "{#BinDir}\openvpn-gui.exe"; DestDir: "{app}\bin"; Flags: ignoreversion uninsneveruninstall
Source: "{#BinDir}\libopenvpn_plap.dll"; DestDir: "{app}\bin"; Flags: ignoreversion uninsneveruninstall skipifsourcedoesntexist

[Run]
Filename: "{app}\bin\openvpn-gui.exe"; Description: "Launch OpenVPN GUI"; Flags: nowait postinstall skipifsilent

[Code]
function OpenVpnInstalled(): Boolean;
begin
  Result := FileExists(ExpandConstant('{commonpf64}\OpenVPN\bin\openvpn.exe'));
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
  Msi: String;
begin
  Result := '';

  { Stop any running GUI so the exe can be replaced }
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM openvpn-gui.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

  if OpenVpnInstalled() then
    exit;

  ExtractTemporaryFile('openvpn.msi');
  Msi := ExpandConstant('{tmp}\openvpn.msi');
  if not Exec(ExpandConstant('{sys}\msiexec.exe'), '/i "' + Msi + '" /qn /norestart', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    Result := 'Could not start msiexec.';
    exit;
  end;
  if (ResultCode <> 0) and (ResultCode <> 3010) then
    Result := 'Official OpenVPN install failed (msiexec exit code ' + IntToStr(ResultCode) + ').';
  if ResultCode = 3010 then
    NeedsRestart := True;
end;

{ Find the MSI product code of the official OpenVPN package }
function FindOpenVpnProductCode(): String;
var
  Root: String;
  Names: TArrayOfString;
  I: Integer;
  DisplayName, UninstallString: String;
begin
  Result := '';
  Root := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';
  if not RegGetSubkeyNames(HKLM64, Root, Names) then
    exit;
  for I := 0 to GetArrayLength(Names) - 1 do
  begin
    if RegQueryStringValue(HKLM64, Root + '\' + Names[I], 'DisplayName', DisplayName)
       and (Pos('OpenVPN ', DisplayName) = 1)
       and RegQueryStringValue(HKLM64, Root + '\' + Names[I], 'UninstallString', UninstallString)
       and (Pos('MsiExec', UninstallString) > 0) then
    begin
      Result := Names[I];
      exit;
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ProductCode: String;
  ResultCode: Integer;
begin
  if CurUninstallStep <> usUninstall then
    exit;

  ProductCode := FindOpenVpnProductCode();
  if ProductCode = '' then
    exit;

  if not UninstallSilent() then
    if MsgBox('Also uninstall OpenVPN itself (openvpn.exe, drivers, GUI)?', mbConfirmation, MB_YESNO) <> IDYES then
      exit;

  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM openvpn-gui.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{sys}\msiexec.exe'), '/x ' + ProductCode + ' /qn /norestart', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if (ResultCode <> 0) and (ResultCode <> 3010) then
    MsgBox('OpenVPN uninstall failed (msiexec exit code ' + IntToStr(ResultCode) + ').', mbError, MB_OK);
end;
