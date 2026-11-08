=================================================================================

        Project SASAMI2k, by Nuclei                      

=================================================================================

        SASAMI is,                               

          "Specially Advanced Synchronized Accessible Media Interchange"     

        Pronounce SASAMI [sasami], not [sasimi]            

=================================================================================

             ActiveMovie2/DirectShow Filter, began on 2000. 1. 13.
             Built on Sasami for Winamp Technology(released in 1999. dec.)
             Coded by Ui-jong Choi(nuclei@shinbiro.com)

=================================================================================

Release ; 2001/08/24 Core #757, SMI Converter #309, Main filter 1921



0. Author

     CHOI, UI JONG (nuclei@shinbiro.com)

     http://www.sasami2k.com

     Supported by Kiwidream.com



1. Comment

     757 comes from 741, not 743 (it's unstable 'cause DShow header was JEDI's)    

     Now, I'm working on Subtitles support via Plugins (with SDKs),
     and Video plugins (Examples and SDKs are not yet, yes, I'm lazy -.-)

     I feel shame that there have been a few improvements,
     I think I should shorten my release cycle (like old times :)

     I will release as soon as possible like guerrilla


2. Changes from 756

     1) Removed Green bottom area, and crash
	caused by new code for DivX4 ;(

     2) Removed Crash when terminated
	After System menu popped-up or ALT+SPACE pressed

     3) OpenDialog is in multilanguage now.

     4) sasami2000.exe now contains ICON.
	caused by compression failure.

     5) ALT+8 bug fixed


3. Changes from 734

     There's no noticable feature change - what a shame ^^;;


     1) Compatible with DivX4 now.
	(no more up-side down, no more crash with win2000)

	DivX4 DShow filter has a bug on it's Output Pin.
	(it doubles SourceLength, so SASAMI crashed)


     2) Faster Video Filter

	2~3% faster than before using MMX (YUY2 only)


     3) Removed Memory leaks

	Not that big but they're gone.


     4) Localizations

	Some people sent me there language files!
	Ve~~ry happy to read them!
	Ukraine, Couple of Russians, French, Swedish
	Thank you very much +_+

	Kai (swedish)
	Zenoviy (Ukraine)
	Yngwar (russian)
	KIEV (russian)
	Megabor (russian)
	SKBo (french)

	* Russians, I took the first mail.


     5) Changed Refresh strategy

	Less crushed video, a little faster


     6) CTRL+F Exception fixed

     7) Crash when terminated fixed

     8) Snap shortcuts (undocumented)

	Press ALT+5 ~ ALT+8, SASAMI snaps to corner