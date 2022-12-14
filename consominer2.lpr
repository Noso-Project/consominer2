program consominer2;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads, UTF8process,
  {$ENDIF}
  Classes, sysutils, consominer2unit, nosodig.crypto,NosoDig.Crypto68b, NosoDig.Crypto68, NosoDig.Crypto65,
  functions, strutils, Noso_TUI, NosoTime;

Type
    TMainThread = class(TThread)
    protected
      procedure Execute; override;
    public
      Constructor Create(CreateSuspended : boolean);
    end;

    TMinerThread = class(TThread)
    private
      TNumber:integer;
    protected
      procedure Execute; override;
    public
      Constructor Create(CreateSuspended : boolean; const Thisnumber:integer);
    end;

    TNosoHashFn = function(S: String): THash32;
      THashLibs = (hl65, hl68, hl69, hl70);

    TNosoHashLib = packed record
      Name: String;
      HashFn: TNosoHashFn;
    end;

CONST
     NOSOHASH_LIBS: array[THashLibs] of TNosoHashLib =
    (
    (Name: 'NosoHash v65'; HashFn: @NosoHash65),
    (Name: 'NosoHash v68'; HashFn: @NosoHash68),
    (Name: 'NosoHash v69'; HashFn: @NosoHash68b),
    (Name: 'NosoHash v70'; HashFn: @NosoHash)
    );

var
  MainThread    : TMainThread;
  MinerThread   : TMinerThread;
  CurrHashLib   : THashLibs;
  PageToShow    : integer;

Constructor TMinerThread.Create(CreateSuspended : boolean; const Thisnumber:integer);
Begin
inherited Create(CreateSuspended);
Tnumber := ThisNumber;
FreeOnTerminate := True;
End;

procedure TMinerThread.Execute;
var
  BaseHash, ThisDiff : string;
  ThisHash : string = '';
  ThisSolution : TSolution;
  MyID : integer;
  ThisPrefix : string = '';
  MyCounter : int64 = 100000000;
  EndThisThread : boolean = false;
  ThreadBest  : string = '00000FFFFFFFFFFFFFFFFFFFFFFFFFFF';
Begin
if MyRunTest then MinimunTargetDiff := '00000';
MyID := TNumber-1;
ThisPrefix := MAINPREFIX+GetPrefix(MyID);
ThisPrefix := AddCharR('!',ThisPrefix,18);
ThreadBest := AddCharR('F',MinimunTargetDiff,32);
While ((not FinishMiners) and (not EndThisThread)) do
   begin
   BaseHash := ThisPrefix+MyCounter.ToString;
   Inc(MyCounter);
   ThisHash := NOSOHASH_LIBS[CurrHashLib].HashFn(BaseHash+PoolMinningAddress);
   ThisDiff := GetHashDiff(TargetHash,ThisHash);
   if ThisDiff<ThreadBest then
      begin
      ThisSolution.Target:=TargetHash;
      ThisSolution.Hash  :=BaseHash;
      ThisSolution.Diff  :=ThisDiff;
      if not MyRunTest then
         begin
         if ThisHash = NosoHashOld(BaseHash+PoolMinningAddress) then
            begin
            AddSolution(ThisSolution);
            end;
         end;
      end;
   if MyRunTest then
      begin
      if MyCounter >= 100000000+HashesForTest then EndThisThread := true;
      end
   else
      begin
      if MyCounter mod 1000 =999 then AddIntervalHashes(1000);
      end;
   end;
DecreaseOMT;
End;

constructor TMainThread.Create(CreateSuspended : boolean);
Begin
inherited Create(CreateSuspended);
FreeOnTerminate := true;
End;

Procedure ClearPoolsScreen();
var
  counter  : integer;
  PoolName : string;
Begin
For counter := 0 to length(ArrSources)-1 do
   begin
   PoolName := Format('%0:-17s',[ArrSources[counter].ip]);
   if length(PoolName)>16 then Setlength(PoolName,16);
   TextOut(3,13+counter,Format('%0:-17s',[PoolName]),Lightgray,black);
   TextOut(62,13+counter,Format('%6s',[ArrSources[counter].shares.ToString+'/'+ArrSources[counter].MaxShares.ToString]),Lightgray,black);
   TextOut(41,13+counter,Format('%12s',[Int2Curr(ArrSources[counter].balance)]),Lightgray,black);
   TextOut(56,13+counter,Format('%3s',[IntToStr(ArrSources[counter].payinterval)]),Lightgray,black);
   end;
U_ClearPoolsScreen := false;
End;

Procedure LaunchMiners();
var
  SourceResult : integer;
  Counter      : integer;
Begin
Setstatusmsg('Syncing...',yellow);
Repeat
   SourceResult := CheckSource;
   If SourceResult=0 then sleep(1000);
until SourceResult>0;
if SourceResult=2 then exit;
U_Headers := true;
ResetIntervalHashes;
FinishMiners := false;
WrongThisPool := 0;
ClearSolutions();
LastSpeedCounter := 100000000;
for counter := 1 to MyCPUCount do
   begin
   MinerThread := TMinerThread.Create(true,counter);
   MinerThread.FreeOnTerminate:=true;
   MinerThread.Start;
   sleep(1);
   end;
SetOMT(MyCPUCount);
U_ActivePool := true;
End;

procedure TMainThread.Execute;
Begin
While not FinishProgram do
   begin
   CheckLog;
   if SolutionsLength > 0 then
      SendPoolShare(GetSolution);
   if ( (blockage>=585) and (Not WaitingNextBlock) ) then
      begin
      FinishMiners     := true;
      WaitingNextBlock := true;
      U_WaitNextBlock  := true;
      ToLog('Started waiting next block');
      UpdateOffset(NTPServers);
      end;
   if ( (blockAge>=10) and (blockage<585) ) then
      begin
      if WaitingNextBlock then
         begin
         WaitingNextBlock := false;
         ClearAllPools();
         U_ClearPoolsScreen := true;
         BlockCompleted := false;
         ActivePool := RandonStartPool;
         U_WaitNextBlock := true;
         end
      else
         begin
         if AllFilled then
            begin
            if not BlockCompleted then
               begin
               BlockCompleted := true;
               Setstatusmsg('All shares completed for this block',green);
               ToLog('All filled on block '+CurrentBlock.ToString);
               end;
            end
         else
            begin
            if GetOMTValue = 0 then
               begin
               //Setstatusmsg('Launching miners...',green);
               LaunchMiners;
               end
            else
               begin
               //DLabel(1,24,'Something went wrong...',70,AlCenter,black,red);
               end;
            end;
         end
      end;
   sleep(10);
   end;
MainThreadIsFinished := true;
End;

Procedure Updateheader();
Begin
TextOut(2,7,format(' Address: %-37s %15s ',[myaddress,Int2Curr(MyAddressBalance)]),lightgray,black);
TextOut(2,8,Format(' Block: %8s | Age: %3s | CPUs: %2s / %2s | Speed: %10s |',[IntToStr(CurrentBlock),IntToStr(CurrBlockAge),
                  IntToStr(MyCPUCount),IntToStr(MaxCPU),HashrateToShow(CurrSpeed)]),lightgray,black);
TextOut(2,9,Format(' Uptime: %8s | Payments: %3s | Received: %12s | %2s |',[Uptime(MinerStartUTC),IntToStr(ReceivedPayments),Int2curr(ReceivedNoso),IntToStr(MyHashLib)]),lightgray,black);
DWindow(1,6,66,10,'',lightgray,black);
TextOut(1,10,LChar[10],lightgray,black);
TextOut(66,10,LChar[8],lightgray,black);
if MyDonation>0 then DLabel(2,6,' '+MyDonation.ToString+' % ',8,AlCenter,black,green);
U_Headers := false;
End;

Procedure UpdateBlockAge();
Begin
TextOut(11,9,Format('%8s',[Uptime(MinerStartUTC)]),Lightgray,black);
TextOut(55,8,Format('%10s',[HashrateToShow(GetTotalHashes)]),Lightgray,black);
TextOut(26,8,Format('%3s',[IntToStr(BlockAge)]),Lightgray,black);
Dlabel(48,25,TimestampToDate(UTCTime),22,Alcenter,white,lightBlue);
GotoXy(1,25);
U_BlockAge := UTCTime;
End;

Procedure UpdateActivePool();
var
  counter  : integer;
  PoolName : string;
Begin
PoolName := Format('%0:-17s',[ArrSources[activepool].ip]);
if length(PoolName)>16 then Setlength(PoolName,16);
DLabel(3,13+ActivePool,PoolName,16,AlLeft,White,Blue);
DLabel(62,13+Activepool,ArrSources[activepool].shares.ToString+'/'+ArrSources[activepool].maxshares.ToString,6,AlRight,white,blue);
DLabel(41,13+Activepool,Int2Curr(ArrSources[activepool].balance),12,AlRight,white,blue);
DLabel(56,13+Activepool,IntToStr(ArrSources[activepool].payinterval),3,AlRight,white,blue);
DLabel(23,13+Activepool,IntToStr(ArrSources[activepool].miners),6,AlRight,lightGray,Black);
DLabel(32,13+Activepool,FormatFloat('0.00',ArrSources[activepool].fee/100),6,AlRight,lightGray,Black);
U_ActivePool := false;
End;

Procedure PrintStatus(LText:String; LColor:integer);
Begin
if WaitingNextBlock then LText := '';
DLabel(1,24,LText,70,AlCenter,LColor,Black);
StatusMsg := '';
End;

Procedure UpdateTotalPending();
Begin
DLabel(41,13+length(ArrSources),Int2Curr(GetTotalPending),12,AlRight,White,green);
U_TotalPending := false;
end;

Procedure UpdateNextBlockMessage();
Begin
DLabel(10,20,'',40,AlCenter,lightGray,black);
if WaitingNextBlock then
   begin
   DLabel(10,20,'Waiting next block',40,AlCenter,White,red);
   SetStatusmsg(' ',white);
   end;
U_WaitNextBlock := false;
End;

Procedure Drawpools();
var
  ThisPool, ThisLine : string;
  PoolName, ThisMiners : string[20];
  Thisfee : integer;
  thisrate : int64;
  Counter : integer;
  DetectedPools : integer = 0;
  ThisBalance   : string;
  ThisPAyInterval : string;
  ThisShares      : string;
Begin
DWindow(1,10,69,12,'',lightgray,black);
TextOut(1,12,LChar[10],lightgray,black);
TextOut(69,12,LChar[6],lightgray,black);
TextOut(2,11,format(' %0:-17s | %6s | %6s | %12s | %3s | %6s ',['Pool','Miners','Fee','Balance','Pay','Shares']),yellow,black);
for counter :=0 to length(ArrSources)-1 do
    begin
    PoolName := Format('%0:-17s',[ArrSources[counter].ip]);
    if length(PoolName)>16 then Setlength(PoolName,16);
    ThisPool := GetPoolInfo(ArrSources[counter].ip,ArrSources[counter].port);
    ThisMiners := Parameter(ThisPool,0);
    thisrate := StrToInt64Def(Parameter(ThisPool,1),0);
    thisfee := StrToIntDef(Parameter(ThisPool,2),0);
    ThisBalance := Int2Curr(ArrSources[counter].balance);
    ThisPayInterval := IntToStr(ArrSources[counter].payinterval);
    ThisShares      := IntToStr(ArrSources[counter].Shares)+'/'+ArrSources[counter].maxshares.ToString;
    TextOut(1,13+counter,format(Lchar[5]+' %-17s '+LChar[5]+' %6s '+LChar[5]+' %6s '+LChar[5]+' %12s '+LChar[5]+' %3s '+LChar[5]+' %6s '+LChar[5],[PoolName,ThisMiners,FormatFloat('0.00',ThisFee/100),ThisBalance,ThisPAyInterval,ThisShares]),lightgray,black);
    Inc(DetectedPools)
    end;
HorizLine(13+DetectedPools,1,69,lightgray,black);
TextOut(1,13+DetectedPools,LChar[9],white,black);
TextOut(69,13+DetectedPools,LChar[7],white,black);
if DetectedPools = 0 then
   begin
   TextOut(1,12,'No pools listed',lightgray,black);
   end;
End;

Procedure UpdateNewPayment();
Begin
DLabel(37,6,Format(' New payment: %12s ',[Int2Curr(U_NewPayment)]),30,AlCenter,white,Green);
Textout(32,9,Format('%3s',[IntToStr(ReceivedPayments)]),lightgray,black);
Textout(46,9,Format('%12s',[Int2Curr(ReceivedNoso)]),lightgray,black);
U_NewPayment := 0;
End;

Procedure UpdateNosoBalance();
Begin
Textout(50,7,format('%15s',[Int2Curr(MyAddressBalance)]),lightgray,black);
U_AddressNosoBalance := false;
End;

Function RunConfig:integer;
var
  IsDone    : integer = 0;
  ActiveRow : integer = 9;
  GetEdit   : TEditData;
  NavKey    : integer;

   procedure showData();
   Begin
   DLabel(22,9,MyAddress,38,AlLeft,lightgray,black);
   DLabel(22,10,MyCPUCount.ToString,38,AlLeft,lightgray,black);
   DLabel(22,11,MyHAshlib.ToString,38,AlLeft,lightgray,black);
   DLabel(22,12,MyMaxShares.ToString,38,AlLeft,lightgray,black);
   DLabel(22,13,MyDonation.ToString,38,AlLeft,lightgray,black);
   Dlabel(2,15,'Save & Run',17,alCenter,black,brown);
   Dlabel(22,15,'Save & Menu',17,alCenter,black,brown);
   Dlabel(42,15,'Menu',17,alCenter,black,brown);
   End;

Begin
Result := 0;
BKColor(black);
cls(1,6,80,25);
DWindow(1,8,60,14,'',white,black);
DLabel(1,6,'Consominer2 Configuration',70,AlCenter,yellow,Green);
VertLine(20,8,14,white,black,true);
TextOut(3,9,'Noso address',yellow,black);
TextOut(3,10,Format('CPUs [%d]',[MaxCPU]),yellow,black);
TextOut(3,11,'Hashlib',yellow,black);
TextOut(3,12,'Block shares',yellow,black);
TextOut(3,13,'Donate %',yellow,black);
showData;
ClrLine(25);
DLabel(1,25,'['#24' '#25'] Navigate',16,AlCenter,white,green);
DLabel(18,25,'[ENTER] Select',16,AlCenter,white,green);
Repeat
   If ActiveRow > 16 then ActiveRow := 9;
   If ActiveRow < 9 then ActiveRow := 16;
   if ActiveRow=9 then
      begin
      GetEdit := ReadEditScreen(22,ActiveRow,MyAddress,38);
      if GetEdit.OutKey = 80 then Inc(ActiveRow);
      if GetEdit.OutKey = 72 then Dec(ActiveRow);
      MyAddress := GetEdit.OutString;
      showData;
      end
   else if ActiveRow = 10 then
      begin
      GetEdit := ReadEditScreen(22,ActiveRow,MyCPUCount.ToString,38);
      if GetEdit.OutKey = 80 then Inc(ActiveRow);
      if GetEdit.OutKey = 72 then Dec(ActiveRow);
      MyCPUCount := StrToIntDef(GetEdit.OutString,MyCPUCount);
      showData;
      end
   else if ActiveRow = 11 then
      begin
      GetEdit := ReadEditScreen(22,ActiveRow,MyHAshlib.ToString,38);
      if GetEdit.OutKey = 80 then Inc(ActiveRow);
      if GetEdit.OutKey = 72 then Dec(ActiveRow);
      MyHAshlib := StrToIntDef(GetEdit.OutString,MyHAshlib);
      showData;
      end
   else if ActiveRow = 12 then
      begin
      GetEdit := ReadEditScreen(22,ActiveRow,MyMaxShares.ToString,38);
      if GetEdit.OutKey = 80 then Inc(ActiveRow);
      if GetEdit.OutKey = 72 then Dec(ActiveRow);
      MyMaxShares := StrToIntDef(GetEdit.OutString,MyMaxShares);
      showData;
      end
   else if ActiveRow = 13 then
      begin
      GetEdit := ReadEditScreen(22,ActiveRow,MyDonation.ToString,38);
      if GetEdit.OutKey = 80 then Inc(ActiveRow);
      if GetEdit.OutKey = 72 then Dec(ActiveRow);
      MyDonation := StrToIntDef(GetEdit.OutString,MyDonation);
      showData;
      end
   else if ActiveRow = 14 then
      begin
      Dlabel(2,15,'Save & Run',17,alCenter,white,Green);
      GotoXy(2,15);
      NavKey := ReadNavigationKey;
      if Navkey = 77 then ActiveRow := 15;
      if Navkey = 72 then ActiveRow := 13;
      if Navkey = 80 then ActiveRow := 9;
      if navkey = 13 then
         begin
         MyRunTest := false;
         Createconfig();
         LoadConfig();
         result:=1;
         IsDone := 1;
         end;
      ShowData;
      end
   else if ActiveRow = 15 then
      begin
      Dlabel(22,15,'Save & Menu',17,alCenter,white,green);
      GotoXy(22,15);
      NavKey := ReadNavigationKey;
      if Navkey = 77 then ActiveRow := 16;
      if Navkey = 75 then ActiveRow := 14;
      if Navkey = 72 then ActiveRow := 13;
      if Navkey = 80 then ActiveRow := 9;
      if navkey = 13 then
         begin
         Createconfig();
         result:=2;
         IsDone := 2;
         end;
      ShowData;
      end
   else if ActiveRow = 16 then
      begin
      Dlabel(42,15,'Menu',17,alCenter,white,green);
      GotoXy(42,15);
      NavKey := ReadNavigationKey;
      if Navkey = 75 then ActiveRow := 15;
      if Navkey = 72 then ActiveRow := 13;
      if Navkey = 80 then ActiveRow := 9;
      if navkey = 13 then
         begin
         result:=3;
         IsDone := 3;
         end;
      ShowData;
      end;
until IsDone<>0;
if IsDone = 1 then PageToShow := 2;    {Miner}
if IsDone = 2 then PageToShow := 1;   {Exit}
if IsDone = 3 then PageToShow := 1;    {menu}
End;

Function RunTest():boolean;
var
  CPUsToUse    : integer;
  LibToUse     : integer;
  TestStart, TestEnd, TestTime : Int64;
  LaunchThread : integer;
  CPUSpeed     : extended;
  ShowResult   : String;
  KeyCode     : integer;
Begin
BKColor(black);
cls(1,6,80,25);
DLabel(1,6,'Consominer2 Test',70,AlCenter,yellow,Green);
GotoXy(1,25);
ClrLine(25);
TextOut(1,25,' Running speed test. Please wait ',White,green);
DWindow(1,8,61,10,'',white,black);
DLabel(2,9,Format(' CPUs  | Hashlib65  | Hashlib68  | Hashlib69  | Hashlib70',[]),59,AlLeft,yellow,black);
TextOut(1,10,LChar[10],white,black);
TextOut(61,10,LChar[6],white,black);
For CPUsToUse := 1 to maxCPU do
   begin
   Dlabel(1,10+CPUsToUse,Format(LChar[5]+' %2s    '+LChar[5]+'            '+LChar[5]+'            '+LChar[5]+'            '+LChar[5]+'            '+LChar[5],[IntToStr(CPUsToUse)]),61,AlLEft,lightGray,black);
   for LibToUse := 0 to 3 do
      begin
      if LibToUse = 0 then CurrHashLib := hl65;
      if LibToUse = 1 then CurrHashLib := hl68;
      if LibToUse = 2 then CurrHashLib := hl69;
      if LibToUse = 3 then CurrHashLib := hl70;
      ShowResult := Format('%10s',['Running ']);
      DLabel(11+(LibToUse*13),10+CPUsToUse,ShowResult,10,AlRight,black, red);
      GotoXy(11+(LibToUse*13),10+CPUsToUse);
      TestStart := GetTickCount64;
      FinishMiners := false;
      SetOMT(CPUsToUse);
      for LaunchThread := 1 to CPUsToUse do
         begin
         MinerThread := TMinerThread.Create(true,LaunchThread);
         MinerThread.FreeOnTerminate:=true;
         MinerThread.Start;
         sleep(1);
         end;
      REPEAT
         sleep(1)
      UNTIL GetOMTValue = 0;
      TestEnd := GetTickCount64;
      TestTime := (TestEnd-TestStart);
      CPUSpeed := HashesForTest/(testtime/1000);
      ShowResult := Format('%11s',[FormatFloat('0.00',CPUSpeed*CPUsToUse)]);
      DLabel(11+(LibToUse*13),10+CPUsToUse,ShowResult,10,AlRight,green, black);
      end;
   end;
HorizLine(11+CpusToUse,1,61,white,black);
TextOut(1,11+cpustouse,LChar[9],white,black);
TextOut(61,11+cpustouse,LChar[7],white,black);
ClrLine(25);
DLabel(1,25,' [Alt+X] Exit ',16,AlCenter,black,LightGray);
DLabel(18,25,' [ESC] Menu ',16,AlCenter,white,blue);
GotoXy(1,25);
Repeat
   sleep(1);
   KeyCode := KeyPressedCode;
until  (KeyCode = 11520) or (KeyCode=283);
if KeyCode = 11520 then PageToShow := 10;  {alt+x}
if KeyCode = 283 then PageToShow := 1;  {alt+x}
End;

Procedure RunMenu();
var
  KeyCode : integer;
Begin
BKColor(black);
cls(1,7,80,25);
DLabel(1,6,'Consominer2 Menu',70,AlCenter,yellow,Green);
DLabel(1,25,' [Alt+X] Exit ',16,AlCenter,black,LightGray);
DLabel(18,25,' [Alt+M] Mine ',16,AlCenter,white,blue);
DLabel(35,25,' [F3] Test ',16,AlCenter,black,brown);
DLabel(52,25,' [F4] Settings ',16,AlCenter,black,lightblue);
Dwindow(10,8,60,16,'',white,black);
Vertline (30,9,15,white,black);
Horizline(10,10,60,white,black,true);
Horizline(12,10,60,white,black,true);
Horizline(14,10,60,white,black,true);
TextOut(12,9,'Freepascal ver',yellow, black);TextOut(32,9,fpcVersion,white, black);
TextOut(12,11,'Release date',yellow, black);TextOut(32,11,ReleaseDate,white, black);
TextOut(12,13,'CPUs/Threads',yellow, black);TextOut(32,13,MaxCPU.ToString,white, black);
TextOut(12,15,'Codepage',yellow, black);TextOut(32,15,GetTextCodePage(Output).ToString,white, black);
Gotoxy(1,25);
Repeat
   sleep(1);
   KeyCode := KeyPressedCode;
until ( (Keycode = 11520) or (Keycode = 12800) or (Keycode = 15616) or (Keycode = 15872) );
if KeyCode = 11520 then PageToShow := 10;  {alt+x}
if KeyCode = 12800 then PageToShow := 2;   {alt+m}
if KeyCode = 15616 then PageToShow := 3;   {F3}
if KeyCode = 15872 then PageToShow := 4;   {F4}
End;

Procedure CloseApp();
Begin
cls;
GotoXy(1,1);
Writeln('Consominer2 Properly closed');
Writeln('Done. Bye!');
End;

Procedure RunMiner();
var
  KeyCode       : integer;
  EndMiner      : boolean = false;
Begin
MyRunTest := false;
FinishProgram := false;
WaitingNextBlock := false;
LoadSources();
BKColor(black);
cls(1,6,80,25);
GotoXy(1,1);
GetTimeOffset(NTPServers);
MinerStartUTC := UTCTime;
if Myhashlib = 65 then CurrHashLib := hl65
else if Myhashlib = 68 then CurrHashLib := hl68
else if Myhashlib = 69 then CurrHashLib := hl69
else CurrHashLib := hl70;
Updateheader;
DLabel(1,25,' [Alt+X] Exit ',16,AlCenter,black,LightGray);
DLabel(18,25,' [F2] Menu ',16,AlCenter,black,Magenta);
Drawpools;
ActivePool := RandonStartPool;
MainThread := TMainThread.Create(true);
MainThread.FreeOnTerminate:=true;
MainThread.Start;
Repeat
   if StatusMsg <> '' then PrintStatus(StatusMsg,StatusColor);
   if U_Headers then UpdateHeader;
   if U_ActivePool then UpdateActivePool;
   if U_ClearPoolsScreen then ClearPoolsScreen;
   if U_WaitNextBlock then UpdateNextBlockMessage;
   if U_AddressNosoBalance then UpdateNosoBalance;
   if U_TotalPending then UpdateTotalPEnding;
   if U_NewPayment>0 then UpdateNewPayment;
   if U_BlockAge <> UTCtime then UpdateBlockAge;
   Sleep(1);
   KeyCode := KeyPressedCode;
until  (KeyCode = 11520) or (Keycode = 15360);
   FinishMiners := true;
   FinishProgram := true;
   DLabel(1,24,'Closing miner...',70,AlCenter,white,red);
   Repeat
      sleep(1);
   until(GetOMTValue = 0);
   DLabel(1,24,'Closing main thread...',70,AlCenter,white,red);
   Repeat
      sleep(1);
   until(MAinThreadIsFinished);
MAinThreadIsFinished := false;
FinishProgram := false;
WaitingNextBlock := false;
if KeyCode = 11520 then PageToShow := 10;
if KeyCode = 15360 then PageToShow := 1;
End;

{$R *.res}

BEGIN
Randomize();
cls;
if not FileExists('consominer2.cfg') then CreateConfig();
if not FileExists('log.txt') then CreateLogFile();
if not FileExists('payments.dat') then CreatePaymentsFile();
if not FileExists('payments.txt') then CreateRAWPaymentsFile();
MaxCPU:= {$IFDEF UNIX}GetSystemThreadCount{$ELSE}GetCPUCount{$ENDIF};
LoadConfig();
CreateConfig();
LoadSources();
LoadPreviousPayments;
TextOut(1,1,'    _____                         _',white,black);
TextOut(1,2,'   / ___/__  ___  ___ ___  __ _  (_)__  ___ ____',white,black);
TextOut(1,3,'  / /__/ _ \/ _ \(_-</ _ \/    \/ / _ \/ -_) __/',white,black);
TextOut(1,4,'  \___/\___/_//_/___/\___/_/_/_/_/_//_/\__/_/',white,black);
TextOut(52,1,'___',green,black);
TextOut(51,2,'|_  |',green,black);
TextOut(50,3,'/ __/',green,black);
TextOut(49,4,'/____',green,black);
DLabel(57,3,'V'+Appver,4,AlLeft,yellow,black);
DLabel(57,4,'PoPw',4,AlLeft,red,black);
if MyRunTest then PageToShow := 1
else PageToShow := 2;
Repeat
   if PageToShow = 1 then RunMenu
   else if PageToShow = 2 then RunMiner
   else if PageToShow = 3 then runtest
   else if PageToShow = 4 then runconfig
until PageToShow = 10;
CloseApp;
END.

