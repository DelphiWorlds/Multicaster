unit MC.IPMCastClient;

// ********** NOTE ************
// This class is an interim measure until Indy supports allowing one or more bindings to fail in TIdIPMCastClient (which may even be never)

interface

uses
  // Indy
  IdGlobal, IdIPMCastBase, IdSocketHandle, IdUDPBase, IdThread;

const
  DEF_IMP_THREADEDEVENT = False;

type
  TIPMCastClient = class;

  TIdIPMCastListenerThread = class(TIdThread)
  protected
    FAcceptWait: integer;
    FBuffer: TIdBytes;
    FBufferSize: integer;
    FIncomingData: TIdSocketHandle;
    procedure Run; override;
  public
    FServer: TIPMCastClient;
    constructor Create(AOwner: TIPMCastClient); reintroduce;
    destructor Destroy; override;
    procedure IPMCastRead;
    property AcceptWait: integer read FAcceptWait write FAcceptWait;
  end;

  TIPMCastReadEvent = procedure(Sender: TObject; const AData: TIdBytes; ABinding: TIdSocketHandle) of object;

  TIPMCastClient = class(TIdIPMCastBase)
  protected
    FBindings: TIdSocketHandles;
    FBufferSize: Integer;
    FCurrentBinding: TIdSocketHandle;
    FListenerThread: TIdIPMCastListenerThread;
    FThreadedEvent: boolean;
    FOnIPMCastRead: TIPMCastReadEvent;
    procedure CloseBinding; override;
    procedure DoIPMCastRead(const AData: TIdBytes; ABinding: TIdSocketHandle); virtual;
    function GetActive: Boolean; override;
    function GetBinding: TIdSocketHandle; override;
    function GetDefaultPort: integer;
    procedure InitComponent; override;
    procedure PacketReceived(const AData: TIdBytes; ABinding: TIdSocketHandle);
    procedure SetBindings(const Value: TIdSocketHandles);
    procedure SetDefaultPort(const AValue: integer);
  public
    destructor Destroy; override;
  published
    property Active;
    property Bindings: TIdSocketHandles read FBindings write SetBindings;
    property BufferSize: Integer read FBufferSize write FBufferSize default ID_UDP_BUFFERSIZE;
    property DefaultPort: integer read GetDefaultPort write SetDefaultPort;
    property IPVersion;
    property MulticastGroup;
    property ReuseSocket;
    property ThreadedEvent: boolean read FThreadedEvent write FThreadedEvent default DEF_IMP_THREADEDEVENT;
    property OnIPMCastRead: TIPMCastReadEvent read FOnIPMCastRead write FOnIPMCastRead;
  end;

implementation

uses
  // RTL
  System.SysUtils,
  // Indy
  IdResourceStringsCore, IdStack, IdStackConsts,
  // DW
  DW.OSLog;

{ TIdIPMCastListenerThread }

constructor TIdIPMCastListenerThread.Create(AOwner: TIPMCastClient);
begin
  inherited Create(True);
  FAcceptWait := 1000;
  FBufferSize := AOwner.BufferSize;
  FBuffer := nil;
  FServer := AOwner;
end;

destructor TIdIPMCastListenerThread.Destroy;
begin
  inherited Destroy;
end;

procedure TIdIPMCastListenerThread.Run;
var
  PeerIP: string;
  PeerPort: TIdPort;
  PeerIPVersion: TIdIPVersion;
  ByteCount: Integer;
  LSocketList, LReadList: TIdSocketList;
  i: Integer;
  LBuffer : TIdBytes;
begin
  SetLength(LBuffer, FBufferSize);

  // create a socket list to select for read
  LSocketList := TIdSocketList.CreateSocketList;
  try
    // fill list of socket handles for reading
    for i := 0 to FServer.Bindings.Count - 1 do
    begin
      LSocketList.Add(FServer.Bindings[i].Handle);
    end;

    // select the handles for reading
    LReadList := nil;
    if LSocketList.SelectReadList(LReadList, AcceptWait) then
    begin
      try
        for i := 0 to LReadList.Count - 1 do
        begin
          // Doublecheck to see if we've been stopped
          // Depending on timing - may not reach here
          // if stopped the run method of the ancestor

          if not Stopped then
          begin
            FIncomingData := FServer.Bindings.BindingByHandle(LReadList[i]);
            if FIncomingData <> nil then
            begin
              ByteCount := FIncomingData.RecvFrom(LBuffer, PeerIP, PeerPort, PeerIPVersion);
              // RLebeau: some protocols make use of 0-length messages, so don't discard
              // them here. This is not connection-oriented, so recvfrom() only returns
              // 0 if a 0-length packet was actually received...
              if ByteCount >= 0 then
              begin
                SetLength(FBuffer, ByteCount);
                CopyTIdBytes(LBuffer, 0, FBuffer, 0, ByteCount);
                FIncomingData.SetPeer(PeerIP, PeerPort, PeerIPVersion);
                if FServer.ThreadedEvent then begin
                  IPMCastRead;
                end else begin
                  Synchronize(IPMCastRead);
                end;
              end;
            end;
          end;
        end;
      finally
        LReadList.Free;
      end;
    end;
  finally
    LSocketList.Free;
  end;
end;

procedure TIdIPMCastListenerThread.IPMCastRead;
begin
  FServer.PacketReceived(FBuffer, FIncomingData);
end;

{ TIPMCastClient }

procedure TIPMCastClient.InitComponent;
begin
  inherited InitComponent;
  BufferSize := ID_UDP_BUFFERSIZE;
  FThreadedEvent := DEF_IMP_THREADEDEVENT;
  FBindings := TIdSocketHandles.Create(Self);
end;

function TIPMCastClient.GetBinding: TIdSocketHandle;
var
  I: Integer;
begin
  if FCurrentBinding = nil then
  begin
    if Bindings.Count < 1 then begin
      if DefaultPort > 0 then begin
        Bindings.Add.IPVersion := IPVersion;
      end else begin
        raise EIdMCastNoBindings.Create(RSNoBindingsSpecified);
      end;
    end;
    for I := 0 to Bindings.Count - 1 do
    try
      Bindings[I].AllocateSocket(Id_SOCK_DGRAM);
      // do not overwrite if the default. This allows ReuseSocket to be set per binding
      if FReuseSocket <> rsOSDependent then begin
        Bindings[I].ReuseSocket := FReuseSocket;
      end;
      Bindings[I].Bind;
      Bindings[I].AddMulticastMembership(FMulticastGroup);
      if FCurrentBinding = nil then
        FCurrentBinding := Bindings[I];
      TOSLog.d('Bound %s to %d in %s', [Bindings[I].IP, Bindings[I].Port, Name]);
    except
      on E: Exception do
        TOSLog.d('Failed to bind to %s in %s', [Bindings[I].IP, Name]);
    end;
    // RLebeau: why only one listener thread total, instead of one per Binding,
    // like TIdUDPServer uses?
    FListenerThread := TIdIPMCastListenerThread.Create(Self);
    FListenerThread.Start;
  end;
  Result := FCurrentBinding;
end;

procedure TIPMCastClient.CloseBinding;
var
  I: integer;
begin
  if FCurrentBinding <> nil then
  begin
    // Necessary here - cancels the recvfrom in the listener thread
    FListenerThread.Stop;
    try
      for i := 0 to Bindings.Count - 1 do
      begin
        if Bindings[I].HandleAllocated then
        begin
          // RLebeau: DropMulticastMembership() can raise an exception if
          // the network cable has been pulled out...
          try
            Bindings[I].DropMulticastMembership(FMulticastGroup);
          except
          end;
        end;
        Bindings[I].CloseSocket;
      end;
    finally
      FListenerThread.WaitFor;
      FreeAndNil(FListenerThread);
      FCurrentBinding := nil;
    end;
  end;
end;

procedure TIPMCastClient.DoIPMCastRead(const AData: TIdBytes; ABinding: TIdSocketHandle);
begin
  if Assigned(OnIPMCastRead) then begin
    OnIPMCastRead(Self, AData, ABinding);
  end;
end;

function TIPMCastClient.GetActive: Boolean;
begin
  // inherited GetActive keeps track of design-time Active property
  Result := inherited GetActive or ((FCurrentBinding <> nil) and FCurrentBinding.HandleAllocated);
end;

function TIPMCastClient.GetDefaultPort: integer;
begin
  result := FBindings.DefaultPort;
end;

procedure TIPMCastClient.PacketReceived(const AData: TIdBytes; ABinding: TIdSocketHandle);
begin
  FCurrentBinding := ABinding;
  DoIPMCastRead(AData, ABinding);
end;

procedure TIPMCastClient.SetBindings(const Value: TIdSocketHandles);
begin
  FBindings.Assign(Value);
end;

procedure TIPMCastClient.SetDefaultPort(const AValue: integer);
begin
  if (FBindings.DefaultPort <> AValue) then begin
    FBindings.DefaultPort := AValue;
    FPort := AValue;
  end;
end;

destructor TIPMCastClient.Destroy;
begin
  Active := False;
  FreeAndNil(FBindings);
  inherited;
end;

end.

