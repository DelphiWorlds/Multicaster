unit MainFrm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants, System.Messaging,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Layouts, FMX.Controls.Presentation, FMX.StdCtrls, FMX.Edit, System.Actions,
  FMX.ActnList, FMX.ScrollBox, FMX.Memo, FMX.ListBox,
  IdGlobal, IdSocketHandle,
  MC.Sender, MC.Receiver; // MC.Hammer ;-)

type
  TfrmMain = class(TForm)
    TopLayout: TLayout;
    StartStopSendButton: TButton;
    PortEdit: TEdit;
    PortEditLayout: TLayout;
    ActionList: TActionList;
    StartStopSendAction: TAction;
    BroadcastEditLayout: TLayout;
    BroadcastEdit: TEdit;
    ReceiveMemo: TMemo;
    StartStopReceiveAction: TAction;
    StartStopReceiveButton: TButton;
    BottomLayout: TLayout;
    ClearButton: TButton;
    AddressesListBox: TListBox;
    procedure StartStopSendActionExecute(Sender: TObject);
    procedure StartStopSendActionUpdate(Sender: TObject);
    procedure StartStopReceiveActionExecute(Sender: TObject);
    procedure StartStopReceiveActionUpdate(Sender: TObject);
    procedure ClearButtonClick(Sender: TObject);
  private
    FReceiver: TMulticastReceiver;
    FSender: TMulticastSender;
    procedure LocalAddressChangeMessageHandler(const Sender: TObject; const M: TMessage);
    procedure ReceiverDataReceivedHandler(Sender: TObject; const AData: TIdBytes; ABinding: TIdSocketHandle);
    procedure UpdateLocalAddresses;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.fmx}

uses
  IdStack,
  MC.Consts, MC.NetworkMonitor;

const
  cDefaultPort = 64218;
  cActiveText: array[Boolean] of string = ('Inactive', 'Active');

{ TForm1 }

constructor TfrmMain.Create(AOwner: TComponent);
begin
  inherited;
  TMessageManager.DefaultManager.SubscribeToMessage(TLocalAddressChangeMessage, LocalAddressChangeMessageHandler);
  FReceiver := TMulticastReceiver.Create(Self);
  FReceiver.Port := cDefaultPort;
  FReceiver.OnDataReceived := ReceiverDataReceivedHandler;
  FSender := TMulticastSender.Create(Self);
  FSender.Port := cDefaultPort;
  FSender.Interval := 1000;
  PortEdit.Text := cDefaultPort.ToString;
  UpdateLocalAddresses;
end;

destructor TfrmMain.Destroy;
begin
  TMessageManager.DefaultManager.Unsubscribe(TLocalAddressChangeMessage, LocalAddressChangeMessageHandler);
  inherited;
end;

procedure TfrmMain.LocalAddressChangeMessageHandler(const Sender: TObject; const M: TMessage);
begin
  UpdateLocalAddresses;
end;

procedure TfrmMain.UpdateLocalAddresses;
var
  I: Integer;
  LAddresses: TIdStackLocalAddressList;
begin
  AddressesListBox.Items.Clear;
  AddressesListBox.Items.Add('IPv4 Multicast Group: ' + cMulticastGroupDefaultIPv4);
  LAddresses := TNetworkMonitor.Current.LocalAddresses;
  for I := 0 to LAddresses.Count - 1 do
  begin
    if LAddresses[I].IPVersion = TIdIPVersion.Id_IPv4 then
      AddressesListBox.Items.Add(LAddresses[I].IPAddress);
  end;
  for I := 0 to LAddresses.Count - 1 do
  begin
    if LAddresses[I].IPVersion = TIdIPVersion.Id_IPv6 then
      AddressesListBox.Items.Add(LAddresses[I].IPAddress);
  end;
end;

procedure TfrmMain.ClearButtonClick(Sender: TObject);
begin
  ReceiveMemo.Lines.Clear;
end;

procedure TfrmMain.StartStopSendActionExecute(Sender: TObject);
begin
  FSender.Broadcast.Text := BroadcastEdit.Text;
  FSender.IsActive := not FSender.IsActive;
  ReceiveMemo.Lines.Add('IPv4 Sender is now: ' + cActiveText[FSender.IsIPv4Active]);
  ReceiveMemo.Lines.Add('IPv6 Sender is now: ' + cActiveText[FSender.IsIPv6Active]);
end;

procedure TfrmMain.StartStopSendActionUpdate(Sender: TObject);
const
  cStartStopText: array[Boolean] of string = ('Start Sender', 'Stop Sender');
begin
  StartStopSendAction.Enabled := FSender.IsActive or (not BroadcastEdit.Text.Trim.IsEmpty and (StrToIntDef(PortEdit.Text, -1) > 0));
  StartStopSendAction.Text := cStartStopText[FSender.IsActive];
end;

procedure TfrmMain.StartStopReceiveActionExecute(Sender: TObject);
begin
  FReceiver.IsActive := not FReceiver.IsActive;
  ReceiveMemo.Lines.Add('IPv4 Receiver is now: ' + cActiveText[FReceiver.IsIPv4Active]);
  ReceiveMemo.Lines.Add('IPv6 Receiver is now: ' + cActiveText[FReceiver.IsIPv6Active]);
end;

procedure TfrmMain.StartStopReceiveActionUpdate(Sender: TObject);
const
  cStartStopText: array[Boolean] of string = ('Start Receiver', 'Stop Receiver');
begin
  StartStopReceiveAction.Enabled := FReceiver.IsActive or (StrToIntDef(PortEdit.Text, -1) > 0);
  StartStopReceiveAction.Text := cStartStopText[FReceiver.IsActive];
end;

procedure TfrmMain.ReceiverDataReceivedHandler(Sender: TObject; const AData: TIdBytes; ABinding: TIdSocketHandle);
begin
  ReceiveMemo.Lines.Add(Format('Received from %s: %s', [ABinding.PeerIP, BytesToString(AData)]));
end;

end.
