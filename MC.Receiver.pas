unit MC.Receiver;

interface

uses
  // RTL
  System.SysUtils, System.Classes, System.Messaging,
  // Indy
  IdGlobal, IdSocketHandle,
  // MC
  MC.IPMCastClient;

type
  TDataReceivedEvent = procedure(Sender: TObject; const Data: TIdBytes; Binding: TIdSocketHandle) of object;

  TMulticastReceiver = class(TDataModule)
    procedure ReceiverIPMCastRead(Sender: TObject; const AData: TIdBytes; ABinding: TIdSocketHandle);
  private
    FIsActive: Boolean;
    FPort: Integer;
    FReceiverIPv4: TIPMCastClient;
    FReceiverIPv6: TIPMCastClient;
    FUseAnyBinding: Boolean;
    FOnDataReceived: TDataReceivedEvent;
    procedure CheckReceiver(const AReceiver: TIPMCastClient);
    procedure ConfigureReceiverBinding(const AReceiver: TIPMCastClient);
    procedure ConfigureReceiverBindingsAll(const AListener: TIPMCastClient);
    procedure EnableReceiver(const AReceiver: TIPMCastClient; const AEnable: Boolean);
    function IsNetworkPresent(const AIPVersion: TIdIPVersion): Boolean;
    procedure LocalAddressChangeMessageHandler(const Sender: TObject; const M: TMessage);
    procedure SetIsActive(const Value: Boolean);
    procedure SetPort(const Value: Integer);
    procedure UpdateReceiverPort(const AReceiver: TIPMCastClient);
    function GetIsIPv4Active: Boolean;
    function GetIsIPv6Active: Boolean;
  protected
    procedure ActiveChange; virtual;
    procedure DoDataReceived(const AData: TIdBytes; ABinding: TIdSocketHandle); virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property IsActive: Boolean read FIsActive write SetIsActive;
    property IsIPv4Active: Boolean read GetIsIPv4Active;
    property IsIPv6Active: Boolean read GetIsIPv6Active;
    property Port: Integer read FPort write SetPort;
    property UseAnyBinding: Boolean read FUseAnyBinding write FUseAnyBinding;
    property OnDataReceived: TDataReceivedEvent read FOnDataReceived write FOnDataReceived;
  end;

var
  MulticastReceiver: TMulticastReceiver;

implementation

{%CLASSGROUP 'System.Classes.TPersistent'}

{$R *.dfm}

uses
  // Indy
  IdStack,
  // MC
  MC.NetworkMonitor, MC.Consts,
  // DW
  DW.OSLog;

constructor TMulticastReceiver.Create(AOwner: TComponent);
begin
  inherited;
  FUseAnyBinding := TOSVersion.Platform <> TOSVersion.TPlatform.pfWindows;
  TMessageManager.DefaultManager.SubscribeToMessage(TLocalAddressChangeMessage, LocalAddressChangeMessageHandler);
  FReceiverIPv4 := TIPMCastClient.Create(Self);
  FReceiverIPv4.Name := 'ReceiverIPv4';
  FReceiverIPv4.IPVersion := TIdIPVersion.Id_IPv4;
  FReceiverIPv4.MulticastGroup := cMulticastGroupDefaultIPv4;
  FReceiverIPv4.OnIPMCastRead := ReceiverIPMCastRead;
  FReceiverIPv6 := TIPMCastClient.Create(Self);
  FReceiverIPv6.Name := 'ReceiverIPv6';
  FReceiverIPv6.IPVersion := TIdIPVersion.Id_IPv6;
  FReceiverIPv6.MulticastGroup := cMulticastGroupDefaultIPv6;
  FReceiverIPv6.OnIPMCastRead := ReceiverIPMCastRead;
end;

destructor TMulticastReceiver.Destroy;
begin
  TMessageManager.DefaultManager.Unsubscribe(TLocalAddressChangeMessage, LocalAddressChangeMessageHandler);
  inherited;
end;

procedure TMulticastReceiver.ConfigureReceiverBindingsAll(const AListener: TIPMCastClient);
var
  I: Integer;
  LBinding: TIdSocketHandle;
  LAddress: TIdStackLocalAddress;
begin
  for I := 0 to TNetworkMonitor.Current.LocalAddresses.Count - 1 do
  begin
    LAddress := TNetworkMonitor.Current.LocalAddresses[I];
    if LAddress.IPVersion = AListener.IPVersion then
    begin
      LBinding := AListener.Bindings.Add;
      LBinding.IPVersion := LAddress.IPVersion;
      LBinding.IP := LAddress.IPAddress;
      LBinding.Port := AListener.DefaultPort;
      // TOSLog.d('Configured receiver binding on IP: %s, Port: %d', [LBinding.IP, LBinding.Port]);
    end;
  end;
end;

procedure TMulticastReceiver.ConfigureReceiverBinding(const AReceiver: TIPMCastClient);
var
  LBinding: TIdSocketHandle;
begin
  AReceiver.Active := False;
  AReceiver.Bindings.Clear;
  LBinding := AReceiver.Bindings.Add;
  LBinding.IPVersion := AReceiver.IPVersion;
  LBinding.IP := cIPAddressesAny[AReceiver.IPVersion];
  LBinding.Port := AReceiver.DefaultPort;
  // TOSLog.d('Configured receiver binding on IP: %s, Port: %d', [LBinding.IP, LBinding.Port]);
end;

procedure TMulticastReceiver.EnableReceiver(const AReceiver: TIPMCastClient; const AEnable: Boolean);
begin
  if AEnable and not AReceiver.Active then
  begin
    if not FUseAnyBinding then
      ConfigureReceiverBindingsAll(AReceiver)
    else
      ConfigureReceiverBinding(AReceiver);
    try
      AReceiver.Active := IsNetworkPresent(AReceiver.IPVersion);
    except
      // This handler is mainly for iOS/macOS when there are apparently no "available" IPv6 addresses to receive on
      on E: Exception do
      begin
        TOSLog.d('Exception attempting to set receiver %s Active: %s', [AReceiver.Name, E.Message]);
      end;
    end;
    if AReceiver.Active then
      TOSLog.d('Receiver %s is Active', [AReceiver.Name])
    else
      TOSLog.d('Could not set receiver %s Active', [AReceiver.Name]);
  end
  else if not AEnable then
    AReceiver.Active := False;
end;

function TMulticastReceiver.GetIsIPv4Active: Boolean;
begin
  Result := FReceiverIPv4.Active;
end;

function TMulticastReceiver.GetIsIPv6Active: Boolean;
begin
  Result := FReceiverIPv6.Active;
end;

function TMulticastReceiver.IsNetworkPresent(const AIPVersion: TIdIPVersion): Boolean;
begin
  Result := TNetworkMonitor.Current.IsNetworkPresent(AIPVersion);
end;

procedure TMulticastReceiver.ReceiverIPMCastRead(Sender: TObject; const AData: TIdBytes; ABinding: TIdSocketHandle);
begin
  if not TNetworkMonitor.Current.IsLocalAddress(ABinding.PeerIP) then
    DoDataReceived(AData, ABinding);
end;

procedure TMulticastReceiver.DoDataReceived(const AData: TIdBytes; ABinding: TIdSocketHandle);
begin
  if Assigned(FOnDataReceived) then
    FOnDataReceived(Self, AData, ABinding);
end;

procedure TMulticastReceiver.ActiveChange;
begin
  //
end;

procedure TMulticastReceiver.CheckReceiver(const AReceiver: TIPMCastClient);
begin
  if FIsActive then
  begin
    EnableReceiver(AReceiver, False);
    EnableReceiver(AReceiver, True);
  end;
end;

procedure TMulticastReceiver.LocalAddressChangeMessageHandler(const Sender: TObject; const M: TMessage);
begin
  CheckReceiver(FReceiverIPv4);
  CheckReceiver(FReceiverIPv6);
end;

procedure TMulticastReceiver.SetIsActive(const Value: Boolean);
begin
  if FIsActive <> Value then
  begin
    EnableReceiver(FReceiverIPv4, Value);
    EnableReceiver(FReceiverIPv6, Value);
    FIsActive := IsIPv4Active or IsIPv6Active;
    ActiveChange;
  end;
end;

procedure TMulticastReceiver.SetPort(const Value: Integer);
begin
  if FPort = Value then
    Exit; // <======
  FPort := Value;
  UpdateReceiverPort(FReceiverIPv4);
  UpdateReceiverPort(FReceiverIPv6);
end;

procedure TMulticastReceiver.UpdateReceiverPort(const AReceiver: TIPMCastClient);
var
  LWasActive: Boolean;
begin
  LWasActive := AReceiver.Active;
  EnableReceiver(AReceiver, False);
  AReceiver.DefaultPort := FPort;
  EnableReceiver(AReceiver, LWasActive);
end;

end.
