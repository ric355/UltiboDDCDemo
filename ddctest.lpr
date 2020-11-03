program ddctest;

{$mode objfpc}{$H+}

{
Ultibo DDC Test application
Richard Metcalfe, November 2020

This application tests the additional BSC2 I2C bus on the Raspberry Pi with
Ultibo, which is not normally accessible as it is supposed to be privately owned
by the GPU. However, the GPU does not actually access this bus once the system
has booted (as far as I can tell from various forum postings), and it seems
that most linux installations will expose it as an I2C device in /dev when you
plug in a monitor, and therefore it is reasonably safe to use it. It is certainly
safe enough to read the EDID on address 50, which is what this application does.

Note that Device Data Channel also enables control of some monitors for things
like brightness, contrast etc. This is a separate set of commands and not all
monitors support them.
}


uses
  {$ifdef RPI1}
  RaspberryPi,
  BCM2835,
  BCM2708,
  {$endif}
  {$ifdef ZERO}
  RaspberryPi,
  BCM2835,
  BCM2708,         {driver for the Raspberry Pi SD host}
  {$endif}
  {$ifdef RPI2}
  RaspberryPi2,
  BCM2836,
  BCM2709,         {driver for the Raspberry Pi SD host}
  {$endif}
  {$ifdef RPI3}
  RaspberryPi3,
  BCM2837,
  BCM2710,
  {$endif}
  GlobalConfig,
  GlobalConst,
  GlobalTypes,
  Platform,
  Threads,
  SysUtils,
  Classes,
  Ultibo,
  Console,
  FileSystem,
  FATFS,
  SMSC95XX,
  Shell,
  ShellFilesystem,
  ShellUpdate,
  RemoteShell,
  logoutput,
  framebuffer,
  i2c,
  devices
  ;

const
  // this is the pattern that signals the start of the EDID.
  // note the EDID is repeatedly broadcast by the monitor on address 0x50 and
  // that is why this sync pattern is needed.
  edidsyncpattern : array[1..8] of byte = ($00, $ff, $ff, $ff, $ff, $ff, $ff, $00);

  // this is the time we will wait before giving up on receiving the EDID
  SYNC_TIME_MS = 10000;

  // this is the slave I2C address on which the monitor will continuously broadcast
  // the EDID.
  EDID_I2C_ADDRESS = $50;

type
  // The descriptors have an internal format depending on their type
  // this is just a basic definition to allow each descriptor to be referenced.
  TDescriptorArray = array[1..18] of byte;

  TEdid = record
    manufacturerid : word;
    productcode : word;
    serialnumber : dword;
    manufactureweek : byte;
    manufactureyear : byte;
    edidversion : byte;
    edidrevision : byte;
    videoinputparameters : array[1..5] of byte;
    chromaticitycoords : array[1..10] of byte;
    timingbitmap : array[1..3] of byte;
    timinginformation : array[1..16] of byte;
    descriptor1 : TDescriptorArray;
    descriptor2 : TDescriptorArray;
    descriptor3 : TDescriptorArray;
    descriptor4 : TDescriptorArray;
    extensioncount : byte;
    checksum : byte;
  end;

var
 I2CDevice:PI2CDevice;
 Count : Longword;
 Value : Byte;
 s, s2 : String;
 EDIDSyncindex : byte = 1;
 EDIDSyncd : boolean = false;
 TimedOut : boolean = false;
 StartofSync : qword;
 ByteCount : integer = 0;
 EDID : TEdid;
 Buf : array[1..10] of Byte;


procedure Log(str : string);
var
  s : string;
begin
  s := DateTimeToStr(Now) +': ' + str;

  ConsoleWindowWriteLn(WindowHandle, s);
end;


procedure DumpDescriptor(id : byte; var desc : TDescriptorArray);
var
 snum : string;
 i : integer;
begin
  if (desc[1] = 0) then
  begin
    case desc[4] of
      $ff :
        begin
          snum := '';
          for i := 1 to 13 do
            snum := snum + chr(desc[i+5]);
          log('Descriptor ' + inttostr(id) + ' is Display Serial Number  : ' + snum);
        end;
      $fc :
        begin
          snum := '';
          for i := 1 to 13 do
            snum := snum + chr(desc[i+5]);
          log('Descriptor ' + inttostr(id) + ' is Display Name           :  ' + snum);
        end;

      $fd :
        begin
          log('Descriptor ' + inttostr(id) + ' is a display range limits descriptor');
        end
      else
        log('descriptor ' + inttostr(id) + ' has descriptor type 0x' + inttohex(desc[4], 2));
    end;
  end
  else
    log('Descriptor ' + inttostr(id) + ' is probably a timing descriptor. Clock=' + inttostr((desc[2] * 256 + desc[1])*10) + 'kHz');
end;

begin
  WindowHandle := ConsoleWindowCreate(ConsoleDeviceGetDefault,CONSOLE_POSITION_FULL,True);

  log('Application started.');

  while not DirectoryExists('C:\') do
  begin
  end;

  Log('File system is ready.');

  // first, find and open the I2C device.
  // The HDMI I2C bus, BSC2, needs to have been added.
  // see the forum for details.

  {$ifdef RPI1}
  // if you compile this code and it fails to find the constant BCM_2708_I2C2_DESCRIPTION
  // then that means you have not added the required code to expose the GPU's I2C bus
  // to the ultibo core.
  I2CDevice:=PI2CDevice(DeviceFindByDescription(BCM2708_I2C2_DESCRIPTION));
  {$endif}
  {$ifdef RPIZERO}
  // if you compile this code and it fails to find the constant BCM_2708_I2C2_DESCRIPTION
  // then that means you have not added the required code to expose the GPU's I2C bus
  // to the ultibo core.
  I2CDevice:=PI2CDevice(DeviceFindByDescription(BCM2708_I2C2_DESCRIPTION));
  {$endif}
  {$ifdef RPI2}
  // if you compile this code and it fails to find the constant BCM_2709_I2C2_DESCRIPTION
  // then that means you have not added the required code to expose the GPU's I2C bus
  // to the ultibo core.
  I2CDevice:=PI2CDevice(DeviceFindByDescription(BCM2709_I2C2_DESCRIPTION));
  {$endif}
  {$ifdef RPI3}
  // if you compile this code and it fails to find the constant BCM_2710_I2C2_DESCRIPTION
  // then that means you have not added the required code to expose the GPU's I2C bus
  // to the ultibo core.
  I2CDevice:=PI2CDevice(DeviceFindByDescription(BCM2710_I2C2_DESCRIPTION));
  {$endif}

  if (I2CDevice = nil) then
    log('Failed to find I2C device. Make sure the customisation to add BSC2 to your Ultibo installation is present, and that you have rebuilt the Ultibo libraries.')
  else
  begin
    if I2CDeviceStart(I2CDevice, 100000) <> ERROR_SUCCESS then
    begin
      log('Failed to start I2C Device.');
    end
    else
    begin
      // first, sync on the edid header.

      Log('Attempting to sync with the EDID header...');

      EDIDSyncindex := 1;
      StartofSync:= GetTickCount64;

      while (not EDIDSyncd) and (not TimedOut) do
      begin
        if I2CDeviceRead(I2CDevice, EDID_I2C_ADDRESS, @Value, SizeOf(Byte), Count) = ERROR_SUCCESS then
        begin
          if (Value = edidsyncpattern[EDIDSyncindex]) then
          begin
            EDIDSyncindex := EDIDSyncindex + 1;
            if (EDIDSyncindex = 9) then
            begin
              EDIDSyncd := true;
              log('Synchronized with EDID message header.');
            end;
          end
          else
            EDIDSyncindex := 1;    // if we don't get a match we must start again.
        end;

        TimedOut := GetTickCount64 > StartOfSync + SYNC_TIME_MS;

      end;

      if (not TimedOut) then
      begin

        // now we have sychronized with the EDID header, we can read the following
        // bytes into the structure.

        s := '';
        s2 := '';

        while (ByteCount < 300) do
        begin
          if I2CDeviceRead(I2CDevice, $50, @Value, SizeOf(Byte), Count) = ERROR_SUCCESS then
          begin
            // store byte into the structure
            if (ByteCount < 120) then
              PByte((@EDID) + ByteCount)^ := value
            else
            begin
              // this is overflow data that doesn't fit in the structure
              // shouldn't appear but it might; depends on the monitor.
              s := s + IntToHex(Value, 2) + ' ';
            end;

            ByteCount := ByteCount + 1;
          end;
        end;

        Log('Additional EDID bytes (for extensions) : ' + s);

        Log('Serial number     : ' + inttostr(EDID.serialnumber));
        Log('Manufacture Year  : ' + inttostr(EDID.manufactureyear+1990));
        Log('EDID Version      : ' + inttostr(EDID.edidversion) + '.' + inttostr(EDID.edidrevision));
        Log('Extension Count   : ' + inttostr(EDID.extensioncount));
        Log('Checksum          : ' + inttostr(EDID.checksum));

        DumpDescriptor(1, EDID.descriptor1);
        DumpDescriptor(2, EDID.descriptor2);
        DumpDescriptor(3, EDID.descriptor3);
        DumpDescriptor(4, EDID.descriptor4);

      end
      else
         Log('Failed to synchronize on the EDID header before the timeout occurred.');
    end;
  end;


end.

