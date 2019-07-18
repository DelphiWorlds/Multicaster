unit MC.Consts;

interface

uses
  // Indy
  IdGlobal;

const
  // cMulticastGroupDefaultIPv4 = '239.192.2.204';
  // cMulticastGroupDefaultIPv4 = '230.0.0.1';
  cMulticastGroupDefaultIPv4 = '224.0.1.0';
  // cMulticastGroupDefaultIPv6 = 'FF08:0:0:0:0:0:0:2CC';
  cMulticastGroupDefaultIPv6 = 'FF02::1';
  cMulticastGroupDefaults: array[TIdIPVersion] of string = (cMulticastGroupDefaultIPv4, cMulticastGroupDefaultIPv6);
  cIPAddressesAny: array[TIdIPVersion] of string = ('0.0.0.0', '::');

  cActiveCaptions: array[Boolean] of string = ('Inactive', 'Active');

implementation

end.
