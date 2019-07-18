unit MC.IPMCastServer;

// ********** NOTE ************
// This class is an interim measure until Indy supports multiple bindings in TIdIPMCastServer (which may even be never)

interface

uses
  // Indy
  IdComponent, IdGlobal, IdIPMCastBase, IdSocketHandle;

const
  DEF_IMP_LOOPBACK = True;
  DEF_IMP_TTL = 1;

type
  TIPMCastServer = class(TIdIPMCastBase)
  protected
    FBindings: TIdSocketHandles;
    FCurrentBinding: TIdSocketHandle;
    FLoopback: Boolean;
    FTimeToLive: Byte;
    procedure ApplyLoopback;
    procedure ApplyTimeToLive;
    procedure CloseBinding; override;
    function GetActive: Boolean; override;
    function GetBinding: TIdSocketHandle; override;
    procedure InitComponent; override;
    procedure MulticastBuffer(const AHost: string; const APort: Integer; const ABuffer : TIdBytes);
    procedure SetLoopback(const AValue: Boolean); virtual;
    procedure SetTimeToLive(const AValue: Byte); virtual;
  public
    destructor Destroy; override;
    procedure Send(const AData: string; AByteEncoding: IIdTextEncoding = nil); overload;
    procedure Send(const ABuffer : TIdBytes); overload;
    property Bindings: TIdSocketHandles read FBindings;
  published
    property Active;
    property Loopback: Boolean read FLoopback write SetLoopback default DEF_IMP_LOOPBACK;
    property MulticastGroup;
    property IPVersion;
    property Port;
    property ReuseSocket;
    property TimeToLive: Byte read FTimeToLive write SetTimeToLive default DEF_IMP_TTL;
  end;

implementation

uses
  // RTL
  System.SysUtils, System.Classes,
  // Indy
  IdResourceStringsCore, IdStack, IdStackConsts,
  // DW
  DW.OSLog,
  // MC
  MC.NetworkMonitor;

type
  TIdSocketHandleHelper = class helper for TIdSocketHandle
  public
    procedure EnableMulticastInterface;
  end;

{ TIdSocketHandleHelper }

// Refer to: https://github.com/IndySockets/Indy/issues/203
procedure TIdSocketHandleHelper.EnableMulticastInterface;
var
  LInterfaceIndex: Integer;
begin
  if (IPVersion = TIdIPVersion.Id_IPv6) and TNetworkMonitor.Current.InterfaceIndexes.TryGetValue(IP, LInterfaceIndex) then
    SetSockOpt(Id_IPPROTO_IPv6, Id_IPV6_MULTICAST_IF, LInterfaceIndex);
end;

{ TIPMCastServer }

procedure TIPMCastServer.InitComponent;
begin
  inherited InitComponent;
  FLoopback := DEF_IMP_LOOPBACK;
  FTimeToLive := DEF_IMP_TTL;
  FBindings := TIdSocketHandles.Create(Self);
end;

destructor TIPMCastServer.Destroy;
begin
  Active := False;
  inherited Destroy;
end;

procedure TIPMCastServer.CloseBinding;
var
  I: Integer;
begin
  for I := 0 to Bindings.Count - 1 do
    Bindings[I].CloseSocket;
  FCurrentBinding := nil;
end;

function TIPMCastServer.GetActive: Boolean;
begin
  Result := (FCurrentBinding <> nil) and FCurrentBinding.HandleAllocated;
end;

function TIPMCastServer.GetBinding: TIdSocketHandle;
var
  I: Integer;
begin
  if FCurrentBinding = nil then
  begin
    for I := 0 to Bindings.Count - 1 do
    begin
      if Bindings[I].HandleAllocated then
      begin
        if FCurrentBinding = nil then
          FCurrentBinding := Bindings[I];
        Continue;
      end;
      Bindings[I].AllocateSocket(Id_SOCK_DGRAM);
      Bindings[I].ReuseSocket := FReuseSocket;
      try
        Bindings[I].Bind;
        Bindings[I].EnableMulticastInterface;
        if FCurrentBinding = nil then
          FCurrentBinding := Bindings[I];
        TOSLog.d('Bound to: %s', [Bindings[I].IP]);
      except
        on E: Exception do
        begin
          // Instead of allowing an exception to escape, handle it in case the IP cannot be bound to (i.e. just ignore it)
          Bindings[I].CloseSocket;
          TOSLog.d('Failed to bind to: %s, with error: %s', [Bindings[I].IP, E.Message]);
        end;
      end;
    end;
    ApplyTimeToLive;
    ApplyLoopback;
  end;
  Result := FCurrentBinding;
end;

procedure TIPMCastServer.MulticastBuffer(const AHost: string; const APort: Integer; const ABuffer : TIdBytes);
var
  I: Integer;
begin
  if not IsValidMulticastGroup(AHost) then
    raise EIdMCastNotValidAddress.Create(RSIPMCastInvalidMulticastAddress);
  for I := 0 to Bindings.Count - 1 do
  begin
    if Bindings[I].HandleAllocated then
    try
      Bindings[I].SendTo(AHost, APort, ABuffer, Bindings[I].IPVersion);
    except
      on E: Exception do
      begin
        // TODO: Add a handler for send exceptions
        TOSLog.d('Failed to send on: %s, with error: %s', [Bindings[I].IP, E.Message]);
      end;
    end;
  end;
end;

procedure TIPMCastServer.Send(const AData: string; AByteEncoding: IIdTextEncoding = nil);
begin
  MulticastBuffer(FMulticastGroup, FPort, ToBytes(AData, AByteEncoding));
end;

procedure TIPMCastServer.Send(const ABuffer : TIdBytes);
begin
  MulticastBuffer(FMulticastGroup, FPort, ABuffer);
end;

procedure TIPMCastServer.SetLoopback(const AValue: Boolean);
begin
  if FLoopback <> AValue then
  begin
    FLoopback := AValue;
    ApplyLoopback;
  end;
end;

procedure TIPMCastServer.SetTimeToLive(const AValue: Byte);
begin
  if FTimeToLive <> AValue then
  begin
    FTimeToLive := AValue;
    ApplyTimeToLive;
  end;
end;

procedure TIPMCastServer.ApplyLoopback;
var
  I: Integer;
begin
  for I := 0 to Bindings.Count - 1 do
  begin
    if Bindings[I].HandleAllocated then
      Bindings[I].SetLoopBack(FLoopback);
  end;
end;

procedure TIPMCastServer.ApplyTimeToLive;
var
  I: Integer;
begin
  for I := 0 to Bindings.Count - 1 do
  begin
    if Bindings[I].HandleAllocated then
      Bindings[I].SetMulticastTTL(FTimeToLive);
  end;
end;

end.

