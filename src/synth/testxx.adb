with GNAT.OS_Lib; use GNAT.OS_Lib;
with Version;

with Ghdlmain; use Ghdlmain;
with Ghdlsynth;
with Options;
with Errorout.Console;
with Netlists; use Netlists;

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Types; use Types;


procedure testxx is
      Args : Argument_List (1 .. Ada.Command_Line.Argument_Count);
      Res : Module;
      Cmd : Command_Acc;
      First_Arg : Natural;
begin
   Put_Line ("Hello WORLD!");
   Ghdlsynth.Register_Commands;
   Options.Initialize;
   Errorout.Console.Install_Handler;
   Put_Line ("Hello WORLD!");
   Put_Line (Version.Ghdl_Ver);

   for I in 1 .. Args'Length loop
      begin
      Args (I) := new String'(Ada.Command_Line.Argument(I));
      Put(Natural'Image(I));
      Put(" >> ");
      Put_Line(Ada.Command_Line.Argument(I));
      end;
   end loop;
   Decode_Command_Options ("--synth", Cmd, Args, First_Arg);

   --  Do the real work!
   Res := Ghdlsynth.Ghdl_Synth (Args (First_Arg .. Args'Last));
   Put_Line(Uns32'Image(Uns32(Res)));
end testxx;
