unit MC.Sender;

interface

uses
  // RTL
  System.SysUtils, System.Classes, System.Messaging,
  // Indy
  IdGlobal, IdSocketHandle, IdIPAddrMon, IdBaseComponent, IdComponent, IdIPMCastBase, IdIPMCastServer, IdStack,
  // DW
  DW.ThreadedTimer,
  // Multicaster
  MC.IPMCastServer;

type
  TMulticastSender = class(TDataModule)
  private
    FBroadcast: TStrings;
    FBroadcastTimer: TThreadedTimer;
    FIsActive: Boolean;
    FPort: Integer;
    FServerIPv4: TIPMCastServer;
    FServerIPv6: TIPMCastServer;
    procedure BroadcastTimerIntervalHandler(Sender: TObject);
    procedure CheckServer(const AServer: TIPMCastServer);
    procedure ConfigureServerBindings(const AServer: TIPMCastServer);
    procedure EnableServer(const AServer: TIPMCastServer; const AEnable: Boolean);
    function GetInterval: Integer;
    function IsNetworkPresent(const AIPVersion: TIdIPVersion): Boolean;
    procedure LocalAddressChangeMessageHandler(const Sender: TObject; const M: TMessage);
    procedure SendServerBroadcast(const AServer: TIPMCastServer);
    procedure SetInterval(const Value: Integer);
    procedure SetIsActive(const Value: Boolean);
    procedure SetPort(const Value: Integer);
    procedure UpdateServerPort(const AServer: TIPMCastServer);
    function GetIsIPv4Active: Boolean;
    function GetIsIPv6Active: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Broadcast: TStrings read FBroadcast;
    property Interval: Integer read GetInterval write SetInterval;
    property IsActive: Boolean read FIsActive write SetIsActive;
    property IsIPv4Active: Boolean read GetIsIPv4Active;
    property IsIPv6Active: Boolean read GetIsIPv6Active;
    property Port: Integer read FPort write SetPort;
  end;

var
  MulticastSender: TMulticastSender;

implementation

{%CLASSGROUP 'FMX.Controls.TControl'}

{$R *.dfm}

uses
  // MC
  MC.NetworkMonitor, MC.Consts,
  // DW
  DW.OSLog;

type
  TIPMCastServerHelper = class helper for TIPMCastServer
  public
    function GetBoundAddresses: string;
  end;

{ TIPMCastServerHelper }

function TIPMCastServerHelper.GetBoundAddresses: string;
var
  I: Integer;
  LAddresses: TStrings;
begin
  Result := '';
  LAddresses := TStringList.Create;
  try
    for I := 0 to Bindings.Count - 1 do
    begin
      if Bindings[I].HandleAllocated then
        LAddresses.Add(Bindings[I].IP);
    end;
    Result := LAddresses.CommaText;
  finally
    LAddresses.Free;
  end;
end;

{ TNetworkService }

constructor TMulticastSender.Create(AOwner: TComponent);
begin
  inherited;
  TMessageManager.DefaultManager.SubscribeToMessage(TLocalAddressChangeMessage, LocalAddressChangeMessageHandler);
  FBroadcastTimer := TThreadedTimer.Create(nil);
  FBroadcastTimer.OnTimer :=  BroadcastTimerIntervalHandler;
  FBroadcast := TStringList.Create;
  FServerIPv4 := TIPMCastServer.Create(Self);
  FServerIPv4.Name := 'ServerIPv4';
  FServerIPv4.IPVersion := TIdIPVersion.Id_IPv4;
  FServerIPv4.MulticastGroup := cMulticastGroupDefaults[FServerIPv4.IPVersion];
  FServerIPv6 := TIPMCastServer.Create(Self);
  FServerIPv6.Name := 'ServerIPv6';
  FServerIPv6.IPVersion := TIdIPVersion.Id_IPv6;
  FServerIPv6.MulticastGroup := cMulticastGroupDefaults[FServerIPv6.IPVersion];
end;

destructor TMulticastSender.Destroy;
begin
  TMessageManager.DefaultManager.Unsubscribe(TLocalAddressChangeMessage, LocalAddressChangeMessageHandler);
  FBroadcastTimer.Enabled := False;
  FBroadcast.Free;
  inherited;
end;

function TMulticastSender.GetInterval: Integer;
begin
  Result := FBroadcastTimer.Interval;
end;

function TMulticastSender.GetIsIPv4Active: Boolean;
begin
  Result := FServerIPv4.Active;
end;

function TMulticastSender.GetIsIPv6Active: Boolean;
begin
  Result := FServerIPv6.Active;
end;

function TMulticastSender.IsNetworkPresent(const AIPVersion: TIdIPVersion): Boolean;
begin
  Result := TNetworkMonitor.Current.IsNetworkPresent(AIPVersion);
end;

procedure TMulticastSender.LocalAddressChangeMessageHandler(const Sender: TObject; const M: TMessage);
begin
  TOSLog.d('TMulticastSender.LocalAddressChangeMessageHandler');
  CheckServer(FServerIPv4);
  CheckServer(FServerIPv6);
end;

procedure TMulticastSender.BroadcastTimerIntervalHandler(Sender: TObject);
begin
  SendServerBroadcast(FServerIPv4);
  SendServerBroadcast(FServerIPv6);
end;

procedure TMulticastSender.CheckServer(const AServer: TIPMCastServer);
begin
  if FIsActive then
  begin
    EnableServer(AServer, False);
    EnableServer(AServer, True);
  end;
end;

procedure TMulticastSender.EnableServer(const AServer: TIPMCastServer; const AEnable: Boolean);
begin
  if AEnable and not AServer.Active then
  begin
    ConfigureServerBindings(AServer);
    TOSLog.d('Enabling server: %s', [AServer.Name]);
    AServer.Active := True;
  end
  else if not AEnable then
    AServer.Active := False;
end;

procedure TMulticastSender.ConfigureServerBindings(const AServer: TIPMCastServer);
var
  I: Integer;
  LBinding: TIdSocketHandle;
  LAddress: TIdStackLocalAddress;
begin
  TOSLog.d('Configuring server bindings for: %s', [AServer.Name]);
  AServer.Bindings.Clear;
  for I := 0 to TNetworkMonitor.Current.LocalAddresses.Count - 1 do
  begin
    LAddress := TNetworkMonitor.Current.LocalAddresses[I];
    if (LAddress.IPVersion = AServer.IPVersion) and not LAddress.IPAddress.Equals(cIPAddressesAny[LAddress.IPVersion]) then
    begin
      LBinding := AServer.Bindings.Add;
      LBinding.IPVersion := LAddress.IPVersion;
      LBinding.IP := LAddress.IPAddress;
      LBinding.Port := 0;
      TOSLog.d('Added server binding for: %s', [LBinding.IP]);
    end;
  end;
end;

procedure TMulticastSender.SendServerBroadcast(const AServer: TIPMCastServer);
begin
  if not AServer.Active then
    Exit; // <======
  TOSLog.d('TMulticastSender Sending broadcast on: ' + AServer.GetBoundAddresses);
  AServer.Send(FBroadcast.Text, IndyTextEncoding(IdTextEncodingType.encUTF8));
end;

procedure TMulticastSender.SetInterval(const Value: Integer);
begin
  FBroadcastTimer.Interval := Value;
end;

procedure TMulticastSender.SetIsActive(const Value: Boolean);
begin
  if FIsActive = Value then
    Exit; // <======
  FBroadcastTimer.Enabled := Value;
  EnableServer(FServerIPv4, Value);
  EnableServer(FServerIPv6, Value);
  FIsActive := IsIPv4Active or IsIPv6Active;
end;

procedure TMulticastSender.SetPort(const Value: Integer);
begin
  if FPort = Value then
    Exit; // <======
  FPort := Value;
  UpdateServerPort(FServerIPv4);
  UpdateServerPort(FServerIPv6);
end;

procedure TMulticastSender.UpdateServerPort(const AServer: TIPMCastServer);
var
  LWasActive: Boolean;
begin
  LWasActive := AServer.Active;
  EnableServer(AServer, False);
  AServer.Port := FPort;
  EnableServer(AServer, LWasActive);
end;

end.

