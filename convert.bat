::
:: Copyright 2012, Andras Csizmadia <andras@vpmedia.eu>.
::

:: Echo off and begin localisation of Environment Variables
@ECHO OFF & SETLOCAL

:: Prepare the Command Processor
VERIFY errors 2>nul
SETLOCAL ENABLEEXTENSIONS
IF ERRORLEVEL 1 ECHO Warning: Unable to enable extensions.
SETLOCAL ENABLEDELAYEDEXPANSION

:: Save base directory
PUSHD %CD%
::PUSHD %~dp0

:: Set title
TITLE %~n0

:: STARTUP
echo Converting...
del test\hx\Main.hx /Q
neko bin/As3ToHaxe.n -from test/as3 -to test/hx -useSpaces false