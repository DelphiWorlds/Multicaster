program MulticasterDemo;

uses
  System.StartUpCopy,
  FMX.Forms,
  MainFrm in 'MainFrm.pas' {frmMain},
  MC.Receiver in '..\MC.Receiver.pas' {MulticastReceiver: TDataModule},
  MC.Sender in '..\MC.Sender.pas' {MulticastSender: TDataModule},
  MC.IPMCastClient in '..\MC.IPMCastClient.pas',
  MC.Consts in '..\MC.Consts.pas',
  MC.NetworkMonitor in '..\MC.NetworkMonitor.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
