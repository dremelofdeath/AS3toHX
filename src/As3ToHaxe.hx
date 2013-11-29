/*
 * Copyright (c) 2011, TouchMyPixel & contributors
 * Original author : Tarwin Stroh-Spijer <tarwin@touchmypixel.com>
 * Contributors: Tony Polinelli <tonyp@touchmypixel.com>       
 *               Andras Csizmadia <andras@vpmedia.eu>
 * Reference for further improvements: 
 * http://haxe.org/doc/start/flash/as3migration/part1 
 * http://www.haxenme.org/developers/documentation/actionscript-developers/
 * http://www.haxenme.org/api/  
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   - Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   - Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE TOUCH MY PIXEL & CONTRIBUTERS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE TOUCH MY PIXEL & CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

package;

import sys.FileSystem;
import neko.Lib;
//import neko.Sys;

using StringTools;
using As3ToHaxe;

/**
 * Simple Program which iterates -from folder, finds .mtt templates and compiles them to the -to folder
 */
class As3ToHaxe
{
    public static var keys = ["-from", "-to", "-remove", "-useSpaces", "-flixelSpecific"];
    
    var to:String;
    var from:String; 
    var useSpaces:String;
    var flixelSpecific:String;
    var remove:String;
    var sysargs:Array<String>;
    
    var items:Array<String>;
    
    public static var basePackage:String = "away3d";
    
    private var nameSpaces:Map<String,Ns>;
    private var maxLoop:Int;
    
    static function main() 
    {
        new As3ToHaxe();
    }
    
    public function new()
    {
        maxLoop = 1000;
        
        if (parseArgs())
        {
        
            // make sure that the to directory exists
            if (!FileSystem.exists(to)) FileSystem.createDirectory(to);
            
            // delete old files
            if (remove == "true")
                removeDirectory(to);
            
            items = [];
            // fill items
            recurse(from);

            // to remember namespaces
            nameSpaces = new Map();
            
            for (item in items)
            {
                // make sure we only work wtih AS fiels
                var ext = getExt(item);
                switch(ext)
                {
                    case "as": 
                        doConversion(item);
                }
            }
            
            // build namespace files
            buildNameSpaces();
        }
    }
    
    private function doConversion(file:String):Void
    {        
        var fromFile = file;
        var toFile = to + "/" + file.substr(from.length + 1, file.lastIndexOf(".") - (from.length)) + "hx";

        /* -----------------------------------------------------------*/
        // create the folder if it doesn''t exist
        var dir = toFile.substr(0, toFile.lastIndexOf("/"));
        createFolder(dir);

        var s = sys.io.File.getContent(fromFile);

        s = processFileContents(s, file);
        /* -----------------------------------------------------------*/

        var o = sys.io.File.write(toFile, true);
        o.writeString(s);
        o.close();

        /* -----------------------------------------------------------*/

        // use for testing on a single file
        //Sys.exit(1);
    }

    private function processFileContents(s:String, file:String):String
    {
        var b = 0;

        /* -----------------------------------------------------------*/
        // space to tabs      
        s = quickRegR(s, "    ", "\t");
        
        // undent
        //s = quickRegR(s, "\t\t", "\t");
        
        /* -----------------------------------------------------------*/
        // some quick setup, finding what we''ve got
        var className = quickRegM(s, "public class([ ]*)([A-Z][a-zA-Z0-9_]*)", 2)[1];
        
        /* -----------------------------------------------------------*/
        // package with name
        s = quickRegR(s, "package ([a-zA-Z\\.0-9-_]*)([\n\r\t ]*){", "package $1;\n", "gs");
        
        // package without name
        s = quickRegR(s, "package([\n\r\t ]*){", "package;\n", "gs");

        // remove all class-only references, which are for some reason legal in Flash
        s = quickRegR(s, "^[\t ]*[A-Z][a-zA-Z0-9_]*;", "", "gm");
        
        // remove package close bracket 
        s = quickRegR(s, "\\}([\n\r\t ]*)\\}([\n\r\t ]*)$", "}", "gs");

        /* -----------------------------------------------------------*/
        // trim extra indentation
        s = quickRegR(s, "\n\t", "\n");
        
        /* -----------------------------------------------------------*/
        // trim spaces 
        s = quickRegR(s, "([ ]*):([ ]*)", ":");
        s = quickRegR(s, "([ ]*);([ ]*)", ";");
        s = quickRegR(s, "([ ]*)=([ ]*)", "=");
        s = quickRegR(s, "([ ]*)<([ ]*)", "<"); 
        s = quickRegR(s, "([ ]*)>([ ]*)", ">"); 
        s = quickRegR(s, "([ ]*)<=([ ]*)", "<="); 
        s = quickRegR(s, "([ ]*)>=([ ]*)", ">=");
        s = quickRegR(s, "([ ]*)\\(([ ]*)", "(");
        s = quickRegR(s, "([ ]*)\\)([ ]*)", ")");
        
        /* -----------------------------------------------------------*/
        // rename public class -> class
        s = quickRegR(s, "public class", "class");
                        
        /* -----------------------------------------------------------*/
        
        // remap public interface -> interface
        s = quickRegR(s, "public interface", "interface");

        /* -----------------------------------------------------------*/

        // fix multiple interface implementations/extends
        //s = quickRegR(s, "extends[ ]+([a-zA-Z0-9_]+)[ ]+implements[ ]+([a-zA-Z0-9_]+),", "extends $1, implements $2,");
        var interfacePattern:String = "implements[\r\n\t ]+([a-zA-Z0-9_]+),[\r\n\t ]+([A-Z][a-zA-Z0-9_]+)";
        var interfaceRegex:EReg = new EReg(interfacePattern, "g");
        while (interfaceRegex.match(s)) {
          s = quickRegR(s, interfaceRegex, "implements $1 implements $2");
        }

        /* -----------------------------------------------------------*/
        // remap constructor <name> -> function new
        s = quickRegR(s, "function " + className, "function new");   
                        
        /* -----------------------------------------------------------*/
        
        // casting
        s = quickRegR(s, "([a-zA-Z0-9_.\\[\\]]*) is ([a-zA-Z0-9_.\\[\\]]*)", "Std.is($1, $2)");
        s = quickRegR(s, "\\/\\/(.*)Std\\.is\\(([a-zA-Z0-9_]+), ([a-zA-Z0-9_]+)\\)", "//$1$2 is $3", "gm");
        s = quickRegR(s, "=([a-zA-Z0-9_]*) as ([a-zA-Z0-9_]*)", "=cast($1, $2)");
        s = quickRegR(s, "=([a-zA-Z0-9_.]*(\\(.*\\)))as ([a-zA-Z0-9_]*)", "=cast($1, $3)");
        s = quickRegR(s, "\\(([a-zA-Z0-9_.]+) as ([a-zA-Z0-9_.]+)\\)", "cast($1, $2)");
        //s = quickRegR(s, "([a-zA-Z0-9_]|\\.|\\(|\\))+ as ([a-zA-Z0-9_]|\\.|\\(|\\))+", "cast($1, $2)");
        s = quickRegR(s, "\\([\r\n\t ]*([^\r\n\t ]+) as ([^\r\n\t]+)\\)", "cast($1, $2)");
        s = quickRegR(s, "([a-zA-Z0-9._()[\\]\\-+*/]+) as ([a-zA-Z0-9._()[\\]\\-+*/]+)", "cast($1, $2)");
        
        s = quickRegR(s, " int\\(([a-zA-Z0-9_]*)", " Std.int($1");
        s = quickRegR(s, " Number\\(([a-zA-Z0-9_]*)", " Std.parseFloat($1");
        s = quickRegR(s, " String\\(([a-zA-Z0-9_]*)", " Std.string($1");
        
        s = quickRegR(s, "=int\\(([a-zA-Z0-9_]*)", "=Std.int($1");
        s = quickRegR(s, "=Number\\(([a-zA-Z0-9_]*)", "=Std.parseFloat($1");
        s = quickRegR(s, "=String\\(([a-zA-Z0-9_]*)", "=Std.string($1");
        
        /* -----------------------------------------------------------*/
        // comment out standard metadata
        s = quickRegR(s, "\\[SWF\\(", "//[SWF("); 
        s = quickRegR(s, "\\[Bindable\\(", "//[Bindable("); 
        s = quickRegR(s, "\\[Embed\\(", "//[Embed(");
        s = quickRegR(s, "\\[Event\\(", "//[Event(");
        s = quickRegR(s, "\\[Frame\\(", "//[Frame(");
        
        /* -----------------------------------------------------------*/    
        // simple typing
        s = quickRegR(s, ":void", ":Void");
        s = quickRegR(s, ":Boolean", ":Bool");
        s = quickRegR(s, ":uint", ":Int"); // NME compatibility
        s = quickRegR(s, ":int", ":Int");
        s = quickRegR(s, ":Number", ":Float");
        s = quickRegR(s, ":\\*", ":Dynamic");
        s = quickRegR(s, ":Object", ":Dynamic");
        s = quickRegR(s, ":Function", ":Dynamic");
        s = quickRegR(s, ":Error", ":Dynamic"); // NME compatibility 
        
        s = quickRegR(s, " void", " Void");
        s = quickRegR(s, " Boolean", " Bool");
        s = quickRegR(s, " uint", " Int"); // NME compatibility
        s = quickRegR(s, " int", " Int");
        s = quickRegR(s, " Number", " Float");
        s = quickRegR(s, " Object", " Dynamic");
        s = quickRegR(s, " Function", " Dynamic");
        s = quickRegR(s, " Error", " Dynamic"); // NME compatibility
        
        s = quickRegR(s, "<Boolean>", "<Bool>");
        s = quickRegR(s, "<uint>", "<Int>"); // NME compatibility  
        s = quickRegR(s, "<int>", "<Int>");
        s = quickRegR(s, "<Number>", "<Float>");
        s = quickRegR(s, "<\\*>", "<Dynamic>");
        s = quickRegR(s, "<Object>", "<Dynamic>");
        s = quickRegR(s, "<Function>", "<Dynamic>");
        s = quickRegR(s, "<Error>", "<Dynamic>"); // NME compatibility
        
        /* -----------------------------------------------------------*/
        // vector to array mapping     
        s = quickRegR(s, "Vector([ ]*)\\.([ ]*)<([ ]*)([^>]*)([ ]*)>", "Array<$3$4$5>");
        // new (including removing stupid spaces)
        s = quickRegR(s, "new Vector([ ]*)([ ]*)<([ ]*)([^>]*)([ ]*)>([ ]*)\\(([ ]*)\\)([ ]*)", "new Array()");
        
        // old version:
        /*
        s = quickRegR(s, "Vector([ ]*)\\.([ ]*)<([ ]*)([^>]*)([ ]*)>", "Vector<$3$4$5>");
        // new (including removing stupid spaces)
        s = quickRegR(s, "new Vector([ ]*)([ ]*)<([ ]*)([^>]*)([ ]*)>([ ]*)\\(([ ]*)\\)([ ]*)", "new Vector()");
        // and import if we have to
        var hasVectors = (quickRegM(s, "Vector([ ]*)\\.([ ]*)<([ ]*)([^>]*)([ ]*)>").length != 0);
        if (hasVectors) {
            s = quickRegR(s, "class([ ]*)(" + className + ")", "import flash.Vector;\n\nclass$1$2");
        }
        */

        /* -----------------------------------------------------------*/

        // array
        s = quickRegR(s, "([^a-zA-Z0-9_])Array([ ]*)([;={),])", "$1Array<Dynamic>$3");
        s = quickRegR(s, "([^a-zA-Z0-9_])Array[ ]*$", "$1Array<Dynamic>", "gm");

        // class
        s = quickRegR(s, "([^a-zA-Z0-9_])Class([ ]*)([;={),])", "$1Class<Dynamic>$3");
        s = quickRegR(s, "([^a-zA-Z0-9_])Class[ ]*$", "$1Class<Dynamic>", "gm");

        // varargs -> Array<Dynamic>
        s = quickRegR(s, "(function [a-zA-Z0-9_]+\\(.*)(\\.\\.\\.[ ]*)([a-zA-Z0-9_]+)(.*\\))", "$1$3:Array<Dynamic>$4", "gms");
        s = quickRegR(s, "(function [a-zA-Z0-9_]+\\(.*)(\\.\\.\\.[ ]*)([a-zA-Z0-9_]+)(.*\\))", "$1$3:Array<Dynamic>$4");

        // take type parameterization back for type comparisons
        s = quickRegR(s, "(Std\\.is\\([a-zA-Z0-9._\\[\\]]+, )([A-Z][a-zA-Z0-9_]*)(<[a-zA-Z0-9_<>]+>)\\)", "$1$2)");

        /* -----------------------------------------------------------*/
        
        // remap protected -> private & internal -> private
        s = quickRegR(s, "(protected|internal)[ \t]var", "private var");
        s = quickRegR(s, "(protected|internal)[ \t]const", "private const");
        s = quickRegR(s, "(final[ \t])?(private|protected|internal)[ \t](final[ \t])?function", "private function");
        s = quickRegR(s, "(final[ \t])?(private|protected|internal)[ \t](final[ \t])?override[ \t](final[ \t])?function", "private override function");
        
        /* -----------------------------------------------------------*/
        
        //
        // Namespaces
        //
        
        // find which namespaces are used in this class
        var r = new EReg("([^#])use([ ]+)namespace([ ]+)([a-zA-Z-]+)([ ]*);", "g");
        b = 0;
        while (true) {
            b++; if (b > maxLoop) { logLoopError("namespaces find", file); break; }
            if (r.match(s)) {
                var ns:Ns = {
                    name : r.matched(4),
                    classDefs : new Map()
                };
                nameSpaces.set(ns.name, ns);
                s = r.replace(s, "//" + r.matched(0).replace("use", "#use") + "\nusing " + basePackage + ".namespace." + ns.name.fUpper() +  ";");
            }else {
                break;
            }
        }
        
        // collect all namespace definitions
        // replace them with private
        for (k in nameSpaces.keys()) {
            var n = nameSpaces.get(k);
            b = 0;
            while (true) {
                b++; if (b > maxLoop) { logLoopError("namespaces collect/replace var", file); break; }
                // vars
                var r = new EReg(n.name + "([ ]+)var([ ]+)", "g");
                s = r.replace(s, "private$1var$2");
                if (!r.match(s)) break;
            }
            b = 0;
            while (true) {
                b++; if (b > maxLoop) { logLoopError("namespaces collect/replace func", file); break; }
                // funcs
                var matched:Bool = false;
                var r = new EReg(n.name + "([ ]+)function([ ]+)", "g");
                if (r.match(s)) matched = true;
                s = r.replace(s, "private$1function$2");
                r = new EReg(n.name + "([ ]+)function([ ]+)get([ ]+)", "g");
                if (r.match(s)) matched = true;
                s = r.replace(s, "private$1function$2get$3");
                r = new EReg(n.name + "([ ]+)function([ ]+)set([ ]+)", "g");
                if (r.match(s)) matched = true;
                s = r.replace(s, "private$1function$2$3set");
                if (!matched) break;
            }
        }
        
        /* -----------------------------------------------------------*/
        // change const to inline statics
        s = quickRegR(s, "([\n\t ]+)(public|private)([ ]*)const([ ]+)([a-zA-Z0-9_]+)([ ]*):", "$1$2$3static inline var$4$5$6:");
        s = quickRegR(s, "([\n\t ]+)(public|private)([ ]*)(static)*([ ]+)const([ ]+)([a-zA-Z0-9_]+)([ ]*):", "$1$2$3$4$5inline var$6$7$8:");
        
        /* -----------------------------------------------------------*/
        // change local const to var
        s = quickRegR(s, "const ", "var ");
        
        /* -----------------------------------------------------------*/
        // move variables being set from var def to top of constructor
        // do NOT do this for const
        // if they're static, leave them there
        // TODO!
        
        /* -----------------------------------------------------------*/
        // Error > flash.Error
        // if " Error (" then add "import flash.Error" to head
        /*var r = new EReg("([ ]+)new([ ]+)Error([ ]*)\\(", "");
        if (r.match(s))
            s = quickRegR(s, "class([ ]*)(" + className + ")", "import flash.Error;\n\nclass$1$2");*/
        
        /* -----------------------------------------------------------*/

        // create getters and setters
        b = 0;
        while (true) {
            b++;
            var d = { get: null, set: null, type: null, ppg: null, pps: null, name: null };
            
            // get
            var r = new EReg("([\n\t ]+)([a-z]+)([ ]*)function([ ]*)get([ ]+)([a-zA-Z_][a-zA-Z0-9_]+)([ ]*)\\(([ ]*)\\)([ ]*):([ ]*)([A-Z][a-zA-Z0-9_]*)", "");
            var m = r.match(s);
            if (m) {
                d.ppg = r.matched(2);
                if (d.ppg == "") d.ppg = "public";
                d.name = r.matched(6);
                d.get = "get_" + d.name;
                d.type = r.matched(11);
            }
            
            // set
            var r = new EReg("([\n\t ]+)([a-z]+)([ ]*)function([ ]*)set([ ]+)([a-zA-Z_][a-zA-Z0-9_]*)([ ]*)\\(([ ]*)([a-zA-Z][a-zA-Z0-9_]*)([ ]*):([ ]*)([a-zA-Z][a-zA-Z0-9_]*)", "");
            var m = r.match(s);
            if (m) {
                if (r.matched(6) == d.get || d.get == null)
                    if (d.name == null) d.name = r.matched(6);
                d.pps = r.matched(2);
                if (d.pps == "") d.pps = "public";
                d.set = "set_" + d.name;
                if (d.type == null) d.type = r.matched(12);
            }
            
            // ERROR
            if (b > maxLoop) { logLoopError("getter/setter: " + d, file); break; }

            // replace get
            if (d.get != null)
                s = quickRegR(s, d.ppg + "([ ]+)function([ ]+)get([ ]+)" + d.name, "private function " + d.get);
            
            // replace set
            if (d.set != null)
                s = quickRegR(s, d.pps + "([ ]+)function([ ]+)set([ ]+)" + d.name, "private function " + d.set);
            
            // make haxe getter/setter OR finish
            if (d.get != null || d.set != null) {
                var gs = (d.ppg != null ? d.ppg : d.pps) + " var " + d.name + "(" + d.get + ", " + d.set + "):" + d.type + ";";
                s = quickRegR(s, "private function " + (d.get != null ? d.get : d.set), gs + "\n \tprivate function " + (d.get != null ? d.get : d.set));
            }else {
                break;
            }
        }

        /* -----------------------------------------------------------*/
        
        // for loops (?)
        // TODO!
        //s = quickRegR(s, "for([ ]*)\\(([ ]*)var([ ]*)([A-Z][a-zA-Z0-9_]*)([.^;]*);([.^;]*);([.^\\)]*)\\)", "");
        //var t = quickRegM(s, "for([ ]*)\\(([ ]*)var([ ]*)([a-zA-Z][a-zA-Z0-9_]*)([.^;]*)", 5);
        //trace(t);
        //for (var i : Int = 0; i < len; ++i)
        
        /* -----------------------------------------------------------*/
        
        // remap for in -> in + Reflect
        s = quickRegR(s, "for[ ]*\\(var[ ]+([a-zA-Z0-9_]+):[a-zA-Z0-9_]+[ ]+in[ ]+([^\r\n\t]*)\\)", "for($1 in Reflect.fields($2))");
        // remap for each in -> in
        s = quickRegR(s, "for[ ]+each\\(var[ ]+([a-zA-Z0-9_]+):[a-zA-Z0-9_]+[ ]+in[ ]+", "for($1 in ");

        /* -----------------------------------------------------------*/
        
        // remap for; <; next;
        s = quickRegR(s, "for\\((var)?([ ]*)([a-zA-Z0-9_]+):?([a-zA-Z0-9_]*)=([0-9]+);([a-zA-Z0-9_]*)([<]*)([^;=]*);([a-zA-Z0-9_.]*)([++]*)", "for($3 in $5...$8");
        // remap for; <=; next;
        s = quickRegR(s, "for\\((var)?([ ]*)([a-zA-Z0-9_]+):?([a-zA-Z0-9_]*)=([0-9]+);([a-zA-Z0-9_]*)([<=]*)([^;=]*);([a-zA-Z0-9_.]*)([++]*)", "for($3 in $5...$8");
                       
        /* -----------------------------------------------------------*/
        
        // remap for each -> for
        s = quickRegR(s, "for each", "for");

        /* -----------------------------------------------------------*/

        // change flash instantiations from Class objects to Type.createInstance()
        s = quickRegR(s, "new ([a-z][a-zA-Z0-9_]*)([^a-zA-Z0-9_(])", "Type.createInstance($1, [])$2");
        s = quickRegR(s, "new ([a-z][a-zA-Z0-9_]*)\\((.*)\\)", "Type.createInstance($1, [$2])");
        // remap shortened nullary constructor calls
        s = quickRegR(s, "new ([a-zA-Z0-9_]+[a-zA-Z0-9_<>]*)([^a-zA-Z0-9_(])", "new $1()$2", "gm");

        /* -----------------------------------------------------------*/

        // remove invalid imports
        s = quickRegR(s, "^import flash\\.[a-z]+\\.[a-z][a-zA-Z0-9_]*;\r?\n", "", "gm");
                
        /* -----------------------------------------------------------*/

        // Flixel-specific things

        var hasImportedGroup:Bool = false;
        var actuallyImportedGroup:Bool = false;
        var hasImportedText:Bool = false;
        var actuallyImportedText:Bool = false;
        var hasImportedTile:Bool = false;
        var actuallyImportedTile:Bool = false;
        var hasImportedUtil:Bool = false;
        var actuallyImportedUtil:Bool = false;
        // TODO(dremelofdeath): This could probably be another function, huh?
        // TODO(dremelofdeath): It's a nit, but imports could be in alphabetic order...
        if (flixelSpecific == "true") {
          s = quickRegR(s, "(import )(org\\.)(flixel\\.)", "$1$3");
          if (new EReg("FlxGroup", "g").match(s)) {
            if (!hasImportedGroup) {
              hasImportedGroup = true;
              s = quickRegR(s, "(import flixel\\.)\\*;", "$1*;\n$1group.*;");
              actuallyImportedGroup = new EReg("import flixel\\.group\\.\\*;", "g").match(s);
            }
            if (actuallyImportedTile) {
              // then just delete the whole line if it's there
              s = quickRegR(s, "^import flixel\\.FlxGroup;\r?\n", "", "gm");
            } else {
              s = quickRegR(s, "^(import flixel\\.)(FlxGroup);", "$1group.$2;", "gm");
            }
          }
          if (new EReg("FlxPoint", "g").match(s)) {
            if (!hasImportedUtil) {
              hasImportedUtil = true;
              s = quickRegR(s, "(import flixel\\.)\\*;", "$1*;\n$1util.*;");
              actuallyImportedUtil = new EReg("import flixel\\.util\\.\\*;", "g").match(s);
            }
            if (actuallyImportedUtil) {
              s = quickRegR(s, "^import flixel\\.FlxPoint;\r?\n", "", "gm");
            } else {
              s = quickRegR(s, "^(import flixel\\.)(FlxPoint);", "$1util.$2;", "gm");
            }
          }
          if (new EReg("FlxText", "g").match(s)) {
            if (!hasImportedText) {
              hasImportedText = true;
              s = quickRegR(s, "(import flixel\\.)\\*;", "$1*;\n$1text.*;");
              actuallyImportedText = new EReg("import flixel\\.text\\.\\*;", "g").match(s);
            }
            if (actuallyImportedText) {
              s = quickRegR(s, "^import flixel\\.FlxText;\r?\n", "", "gm");
            } else {
              s = quickRegR(s, "^(import flixel\\.)(FlxText);", "$1text.$2;", "gm");
            }
          }
          if (new EReg("FlxTilemap", "g").match(s)) {
            if (!hasImportedTile) {
              hasImportedTile = true;
              s = quickRegR(s, "(import flixel\\.)\\*;", "$1*;\n$1tile.*;");
              actuallyImportedTile = new EReg("import flixel\\.tile\\.\\*;", "g").match(s);
            }
            if (actuallyImportedTile) {
              s = quickRegR(s, "^import flixel\\.FlxTilemap;\r?\n", "", "gm");
            } else {
              s = quickRegR(s, "^(import flixel\\.)(FlxTilemap);", "$1tile.$2;", "gm");
            }
          }
          if (new EReg("FlxTile", "g").match(s)) {
            if (!hasImportedTile) {
              hasImportedTile = true;
              s = quickRegR(s, "(import flixel\\.)\\*;", "$1*;\n$1tile.*;");
              actuallyImportedTile = new EReg("import flixel\\.tile\\.\\*;", "g").match(s);
            }
            if (actuallyImportedTile) {
              s = quickRegR(s, "^import flixel\\.system\\.FlxTile;\r?\n", "", "gm");
            } else {
              s = quickRegR(s, "^(import flixel\\.)(system\\.)(FlxTile);", "$1tile.$3;", "gm");
            }
          }

          // Convert to using frontends in HaxeFlixel
          s = quickRegR(s, "FlxG\\.addBitmap\\(", "FlxG.bitmap.add(");
          s = quickRegR(s, "FlxG\\.checkBitmapCache\\(", "FlxG.bitmap.checkCache(");
          s = quickRegR(s, "FlxG\\.clearBitmapCache\\(", "FlxG.bitmap.clearCache(");
          s = quickRegR(s, "FlxG\\.createBitmap\\(", "FlxG.bitmap.create(");

          s = quickRegR(s, "FlxG\\.bgColor", "FlxG.cameras.bgColor");
          s = quickRegR(s, "FlxG\\.cameras", "FlxG.cameras.list");
          s = quickRegR(s, "FlxG\\.useBufferLocking", "FlxG.cameras.useBufferLocking");
          s = quickRegR(s, "FlxG\\.addCamera\\(", "FlxG.cameras.add(");
          s = quickRegR(s, "FlxG\\.fade\\(", "FlxG.cameras.fade(");
          s = quickRegR(s, "FlxG\\.flash\\(", "FlxG.cameras.flash(");
          s = quickRegR(s, "FlxG\\.lockCameras\\(", "FlxG.cameras.lock(");
          s = quickRegR(s, "FlxG\\.removeCamera\\(", "FlxG.cameras.remove(");
          s = quickRegR(s, "FlxG\\.resetCameras\\(", "FlxG.cameras.reset(");
          s = quickRegR(s, "FlxG\\.shake\\(", "FlxG.cameras.shake(");
          s = quickRegR(s, "FlxG\\.unlockCameras\\(", "FlxG.cameras.unlock(");
          s = quickRegR(s, "FlxG\\.updateCameras\\(", "FlxG.cameras.update(");

          s = quickRegR(s, "FlxG\\.visualDebug", "FlxG.debugger.visualDebug");
          s = quickRegR(s, "FlxG\\.resetDebuggerLayout\\(", "FlxG.debugger.resetLayout(");
          s = quickRegR(s, "FlxG\\.setDebuggerLayout\\(", "FlxG.debugger.setLayout(");

          s = quickRegR(s, "FlxG\\.resetInput\\(", "FlxG.inputs.reset(");
          s = quickRegR(s, "FlxG\\.updateInput\\(", "FlxG.inputs.update(");

          s = quickRegR(s, "FlxG\\.log\\(", "FlxG.log.add(");

          s = quickRegR(s, "FlxG\\.plugins", "FlxG.plugins.list");
          s = quickRegR(s, "FlxG\\.addPlugin\\(", "FlxG.plugins.add(");
          s = quickRegR(s, "FlxG\\.drawPlugins\\(", "FlxG.plugins.draw(");
          s = quickRegR(s, "FlxG\\.getPlugin\\(", "FlxG.plugins.get(");
          s = quickRegR(s, "FlxG\\.removePlugin\\(", "FlxG.plugins.remove(");
          s = quickRegR(s, "FlxG\\.removePluginType\\(", "FlxG.plugins.removeType(");
          s = quickRegR(s, "FlxG\\.updatePlugins\\(", "FlxG.plugins.update(");

          s = quickRegR(s, "FlxG\\.sounds", "FlxG.sounds.list");
          s = quickRegR(s, "FlxG\\.music", "FlxG.sounds.music");
          s = quickRegR(s, "FlxG\\.mute", "FlxG.sounds.muted");
          s = quickRegR(s, "FlxG\\.volumeHandler", "FlxG.sounds.volumeHandler");
          s = quickRegR(s, "FlxG\\.volume", "FlxG.sounds.volume");
          s = quickRegR(s, "FlxG\\.destroySounds\\(", "FlxG.sounds.destroySounds(");
          s = quickRegR(s, "FlxG\\.loadSound\\(", "FlxG.sounds.load(");
          s = quickRegR(s, "FlxG\\.pauseSounds\\(", "FlxG.sounds.pauseSounds(");
          s = quickRegR(s, "FlxG\\.play\\(", "FlxG.sounds.play(");
          s = quickRegR(s, "FlxG\\.playMusic\\(", "FlxG.sounds.playMusic(");
          s = quickRegR(s, "FlxG\\.resumeSounds\\(", "FlxG.sounds.resumeSounds(");
          s = quickRegR(s, "FlxG\\.stream\\(", "FlxG.sounds.stream(");
          s = quickRegR(s, "FlxG\\.updateSounds\\(", "FlxG.sounds.updateSounds(");

          s = quickRegR(s, "FlxG\\.watch\\(", "FlxG.watch.add(");
          s = quickRegR(s, "FlxG\\.unwatch\\(", "FlxG.watch.remove(");
        }


        /* -----------------------------------------------------------*/
                
        // use spaces instead of tab
        if(useSpaces == "true")
        {
            s = quickRegR(s, "\t", "    ");
        }

        return s;
    }
    
    private function logLoopError(type:String, file:String)
    {
        trace("ERROR: " + type + " - " + file);
    }
    
    private function buildNameSpaces()
    {
        // build friend namespaces!
        trace(nameSpaces);
    }
    
    public static function quickRegR(str:String, reg:Dynamic, rep:String, ?regOpt:String = "g"):String
    {
      var regex:EReg;
      if (Std.is(reg, String)) {
        regex = new EReg(cast(reg, String), regOpt);
      } else {
        regex = reg;
      }
      return regex.replace(str, rep);
    }
    
    public static function quickRegM(str:String, reg:String, ?numMatches:Int = 1, ?regOpt:String = "g"):Array<String>
    {
        var r = new EReg(reg, regOpt);
        var m = r.match(str);
        if (m) {
            var a = [];
            var i = 1;
            while (i <= numMatches) {
                a.push(r.matched(i));
                i++;
            }
            return a;
        }
        return [];
    }
    
    private function createFolder(path:String):Void
    {
        var parts = path.split("/");
        var folder = "";
        for (part in parts)
        {
            if (folder == "") folder += part;
            else folder += "/" + part;
            if (!FileSystem.exists(folder)) FileSystem.createDirectory(folder);
        }
    }
    
    private function parseArgs():Bool
    {
        // Parse args
        var args = Sys.args();
        for (i in 0...args.length)
            if (Lambda.has(keys, args[i]))
                Reflect.setField(this, args[i].substr(1), args[i + 1]);
            
        // Check to see if argument is missing
        if (to == null) { Lib.println("Missing argument '-to'"); return false; }
        if (from == null) { Lib.println("Missing argument '-from'"); return false; }

        if (flixelSpecific == null) { flixelSpecific = "true"; }
        
        return true;
    }
    
    public function recurse(path:String)
    {
        var dir = FileSystem.readDirectory(path);
        
        for (item in dir)
        {
            var s = path + "/" + item;
            if (FileSystem.isDirectory(s))
            {
                recurse(s);
            }
            else
            {
                var exts = ["as"];
                if(Lambda.has(exts, getExt(item)))
                    items.push(s);
            }
        }
    }
    
    public function getExt(s:String)
    {
        return s.substr(s.lastIndexOf(".") + 1).toLowerCase();
    }
    
    public function removeDirectory(d, p = null)
    {
        if (p == null) p = d;
        var dir = FileSystem.readDirectory(d);

        for (item in dir)
        {
            item = p + "/" + item;
            if (FileSystem.isDirectory(item)) {
                removeDirectory(item);
            }else{
                FileSystem.deleteFile(item);
            }
        }
        
        FileSystem.deleteDirectory(d);
    }
    
    public static function fUpper(s:String)
    {
        return s.charAt(0).toUpperCase() + s.substr(1);
    }
}

typedef Ns = {
    var name:String;
    var classDefs:Map<String,String>;
}
