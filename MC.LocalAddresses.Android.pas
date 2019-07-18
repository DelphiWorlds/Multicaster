unit MC.LocalAddresses.Android;

interface

uses
  IdStack;

procedure GetLocalAddressList(const AAddresses: TIdStackLocalAddressList);

implementation

uses
  // RTL
  System.SysUtils,
  // Android
  Androidapi.JNI.Java.Net, Androidapi.JNI.JavaTypes, Androidapi.Helpers, Androidapi.JNIBridge,
  // Indy
  IdGlobal;

procedure GetLocalAddressList(const AAddresses: TIdStackLocalAddressList);
var
  LInterfaces, LAddresses: JEnumeration;
  LInterface: JNetworkInterface;
  LAddress: JInetAddress;
  LName, LHostAddress: string;
begin
  AAddresses.Clear;
  LInterfaces := TJNetworkInterface.JavaClass.getNetworkInterfaces;
  while LInterfaces.hasMoreElements do
  begin
    LInterface := TJNetworkInterface.Wrap(JObjectToID(LInterfaces.nextElement));
    LAddresses := LInterface.getInetAddresses;
    while LAddresses.hasMoreElements do
    begin
      LAddress := TJInetAddress.Wrap(JObjectToID(LAddresses.nextElement));
      if LAddress.isLoopbackAddress then
        Continue;
      // Hack until I can find out how to check properly
      LName := JStringToString(LAddress.getClass.getName);
      LHostAddress := JStringToString(LAddress.getHostAddress);
      // Trim excess stuff
      if LHostAddress.IndexOf('%') > -1 then
        LHostAddress := LHostAddress.Substring(0, LHostAddress.IndexOf('%'));
      if LName.Contains('Inet4Address') then
        TIdStackLocalAddressIPv4.Create(AAddresses, LHostAddress, '')
      else if LName.Contains('Inet6Address') then
        TIdStackLocalAddressIPv6.Create(AAddresses, LHostAddress);
    end;
  end;
end;

end.
