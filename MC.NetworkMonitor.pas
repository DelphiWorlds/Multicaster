unit MC.NetworkMonitor;

interface

uses
  // RTL
  System.Classes, System.Messaging, System.Generics.Collections,
  // Indy
  IdGlobal, IdStack;

type
  TLocalAddressChangeMessage = class(TMessage);

  TInterfaceIndexes = TDictionary<string, Integer>;

  TNetworkMonitor = class(TObject)
  private
    class var FCurrent: TNetworkMonitor;
    class function GetCurrent: TNetworkMonitor; static;
    class destructor DestroyClass;
  private
    FInterfaceIndexes: TInterfaceIndexes;
    FLocalAddresses: TIdStackLocalAddressList;
    FMessage: TLocalAddressChangeMessage;
    FMonitorThread: TThread;
    procedure UpdateLocalAddresses;
  protected
    procedure LocalAddressesChanged;
  public
    class property Current: TNetworkMonitor read GetCurrent;
  public
    constructor Create;
    destructor Destroy; override;
    function GetLocalAddress(const AIPAddress: string): TIdStackLocalAddress;
    function IsLocalAddress(const AIPAddress: string): Boolean;
    function IsNetworkPresent: Boolean; overload;
    function IsNetworkPresent(const AIPVersion: TIdIPVersion): Boolean; overload;
    property InterfaceIndexes: TInterfaceIndexes read FInterfaceIndexes;
    property LocalAddresses: TIdStackLocalAddressList read FLocalAddresses;
  end;

implementation

uses
  System.SysUtils,
  // MC
{$IF Defined(ANDROID)}
  MC.LocalAddresses.Android,
{$ENDIF}
  // DW
  DW.OSLog;

type
  TMonitorThread = class(TThread)
  private
    FLocalAddresses: TIdStackLocalAddressList;
    FMonitor: TNetworkMonitor;
    function CheckLocalAddressesChanged: Boolean;
    procedure UpdateLocalAddresses;
  protected
    procedure Execute; override;
  public
    constructor Create(const AMonitor: TNetworkMonitor);
    destructor Destroy; override;
  end;

  TIdStackLocalAddressListHelper = class helper for TIdStackLocalAddressList
  public
    function CheckAddressesChanged(const AAddresses: TIdStackLocalAddressList; const AReverse: Boolean = False): Boolean;
    function GetLocalAddress(const AIPAddress: string): TIdStackLocalAddress;
    function IsLocalAddress(const AIPAddress: string): Boolean;
  end;

{ TIdStackLocalAddressListHelper }

function TIdStackLocalAddressListHelper.CheckAddressesChanged(const AAddresses: TIdStackLocalAddressList; const AReverse: Boolean = False): Boolean;
var
  I: Integer;
begin
  Result := Count <> AAddresses.Count;
  if not Result then
  begin
    for I := 0 to AAddresses.Count - 1 do
    begin
      if GetLocalAddress(AAddresses[I].IPAddress) = nil then
      begin
        Result := True;
        Break;
      end;
    end;
  end;
  if not AReverse and not Result then
    Result := AAddresses.CheckAddressesChanged(Self, True);
end;

function TIdStackLocalAddressListHelper.GetLocalAddress(const AIPAddress: string): TIdStackLocalAddress;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to Count - 1 do
  begin
    // Must do a case-insensitive comparison for IPv6 addresses
    if Addresses[I].IPAddress.ToLower = AIPAddress.ToLower then
    begin
      Result := Addresses[I];
      Break;
    end;
  end;
end;

function TIdStackLocalAddressListHelper.IsLocalAddress(const AIPAddress: string): Boolean;
begin
  Result := GetLocalAddress(AIPAddress) <> nil;
end;

{ TMonitorThread }

constructor TMonitorThread.Create(const AMonitor: TNetworkMonitor);
begin
  inherited Create;
  FMonitor := AMonitor;
  FLocalAddresses := TIdStackLocalAddressList.Create;
end;

destructor TMonitorThread.Destroy;
begin
  FLocalAddresses.Free;
  inherited;
end;

procedure TMonitorThread.Execute;
begin
  while not Terminated do
  begin
    if CheckLocalAddressesChanged then
    begin
      TThread.Queue(Self, FMonitor.LocalAddressesChanged);
      Sleep(500);
    end;
    Sleep(500);
  end;
end;

function TMonitorThread.CheckLocalAddressesChanged: Boolean;
begin
  UpdateLocalAddresses;
  Result := FLocalAddresses.CheckAddressesChanged(FMonitor.LocalAddresses);
end;

procedure TMonitorThread.UpdateLocalAddresses;
begin
  FLocalAddresses.Clear;
{$IF Defined(ANDROID)}
  GetLocalAddressList(FLocalAddresses);
{$ELSE}
  GStack.GetLocalAddressList(FLocalAddresses);
{$ENDIF}
end;

{ TNetworkMonitor }

constructor TNetworkMonitor.Create;
begin
  inherited;
  TIdStack.IncUsage;
  if FCurrent = nil then
    FCurrent := Self;
  FMessage := TLocalAddressChangeMessage.Create;
  FInterfaceIndexes := TDictionary<string, Integer>.Create;
  FLocalAddresses := TIdStackLocalAddressList.Create;
  UpdateLocalAddresses;
  FMonitorThread := TMonitorThread.Create(Self);
end;

destructor TNetworkMonitor.Destroy;
begin
  FMessage.Free;
  FMonitorThread.Free;
  FInterfaceIndexes.Free;
  FLocalAddresses.Free;
  TIdStack.DecUsage;
  inherited;
end;

class destructor TNetworkMonitor.DestroyClass;
begin
  FCurrent.Free;
  FCurrent := nil;
end;

class function TNetworkMonitor.GetCurrent: TNetworkMonitor;
begin
  if FCurrent = nil then
    TNetworkMonitor.Create;
  Result := FCurrent;
end;

function TNetworkMonitor.GetLocalAddress(const AIPAddress: string): TIdStackLocalAddress;
begin
  Result := FLocalAddresses.GetLocalAddress(AIPAddress);
end;

function TNetworkMonitor.IsLocalAddress(const AIPAddress: string): Boolean;
begin
  Result := GetLocalAddress(AIPAddress) <> nil;
end;

procedure TNetworkMonitor.LocalAddressesChanged;
begin
  // TOSLog.d('Local address change');
  UpdateLocalAddresses;
  TMessageManager.DefaultManager.SendMessage(nil, FMessage, False);
end;

function TNetworkMonitor.IsNetworkPresent: Boolean;
begin
  Result := FLocalAddresses.Count > 0;
end;

function TNetworkMonitor.IsNetworkPresent(const AIPVersion: TIdIPVersion): Boolean;
var
  I: Integer;
begin
  for I := 0 to FLocalAddresses.Count - 1 do
  begin
    if FLocalAddresses.Addresses[I].IPVersion = AIPVersion then
      Exit(True);
  end;
  Result := False;
end;

procedure TNetworkMonitor.UpdateLocalAddresses;
begin
  FLocalAddresses.Clear;
{$IF Defined(ANDROID)}
  GetLocalAddressList(FLocalAddresses);
{$ELSE}
  GStack.GetLocalAddressList(FLocalAddresses);
{$ENDIF}
end;

end.
