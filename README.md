<p align="center">
  <img src="app/assets/appIcon.png" alt="LDTK-Smartive logo" width="320">
</p>

# LDTK-Smartive

**LDTK-Smartive** is a fork of **Level Designer Toolkit (LDtk)** focused on `.aseprite` workflows, advanced tileset/editor tooling, and fork-specific authoring features while keeping normal LDtk project compatibility.

Links: [Latest Smartive release](https://github.com/RondeI33/ldtk/releases/latest) | [Smartive releases](https://github.com/RondeI33/ldtk/releases) | [Upstream LDtk](https://ldtk.io/) | [Haxe API](https://github.com/deepnight/ldtk-haxe-api)

[![GitHub Repo stars](https://img.shields.io/github/stars/RondeI33/ldtk?color=%23dca&label=%E2%AD%90)](https://github.com/RondeI33/ldtk)
[![GitHub All Releases](https://img.shields.io/github/downloads/RondeI33/ldtk/total?color=%2389b&label=Downloads)](https://github.com/RondeI33/ldtk/releases/latest)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/RondeI33/ldtk/test-windows.yml?branch=master&label=Smartive%20build)](https://github.com/RondeI33/ldtk/actions/workflows/test-windows.yml)

# Getting LDTK-Smartive latest version

Download the latest Windows, macOS, or Linux build from the [LDTK-Smartive releases page](https://github.com/RondeI33/ldtk/releases/latest).

## Smartive icons inside Unity

If you use LDtk projects in Unity, install the editor-only Smartive icon package through Unity Package Manager using this Git URL:

```
https://github.com/RondeI33/ldtk.git?path=/unity/com.rondei33.ldtk-smartive-unity-icons#master
```

The package keeps the normal LDtkUnity/Cammin importer intact and replaces its old Project-window artwork with the LDTK-Smartive logo for `.ldtk`, `.ldtkl`, and `.ldtka` assets. Existing assets are refreshed automatically; a manual **Tools > LDTK-Smartive > Refresh LDtk asset icons** command is also available.

# Building from source

## Requirements

 - **[Haxe compiler](https://haxe.org)**: you need an up-to-date and working Haxe install  to build LDtk.
 - **[NPM](https://nodejs.org/en/download/)**: this package manager is used for various install and packaging scripts. It is packaged with NodeJS.

## Installing required stuff

 - Open a command line **in the `ldtk` root dir**,
 - Install required Haxe libs:
 ```
 haxe setup.hxml
 ```
 - Install Electron locally and other dependencies through NPM (**IMPORTANT**: you need to be in the `app` dir):
 ```
 cd app
 npm i
 ```

## Compiling *master* branch

First, from the root of the repo, build the electron **Main**:

```
haxe main.debug.hxml
```

This should create a `app/assets/main.js` file.

Then, build the electron **Renderer**:

```
haxe renderer.debug.hxml
```

This should create `app/assets/js/renderer.js`.

## Compiling another branch

If you want to try a future version of LDtk, you can checkout branches named `dev-x.y.z` where x.y.z is version number.

**IMPORTANT**:
 - these *dev* branches might be unstables, or even broken. Therefore, it's not recommended to use, unless you plan to add or fix something on LDtk.
 - because *dev* branches might change quickly, you will need to update haxelibs often.
 - you will need to switch the *LDtk haxe API* to the **same** branch as LDtk repo. (adapt the branch name below accordingly):

```
haxelib git ldtk-haxe-api https://github.com/deepnight/ldtk-haxe-api.git dev-0.6.0
```

## Running

From a command line in the `app` folder, run:

```
npm run start
```

## Running inside Hide (as an editor plugin)

LDtk can run embedded in a [Hide](https://github.com/heapsio/hide) tab.

First build the plugin (from the `ldtk` root dir):

```
haxe hide-plugin.hxml
```

This creates `app/nwjs/hide-plugin.js` (sources in `src/hide/plugin/`). Then add to the Hide project's `res/props.json` (`ldtk.project` is optional and resolves relative to `res/`):

```json
"plugins": [ "/path/to/ldtk/app/nwjs/hide-plugin.js" ],
"menu.extra": "<menu label='LDtk' component='ldtk.LdtkView'></menu>",
"ldtk.project": "path/to/world.ldtk"
```

LDtk then opens from the menu, in its own tab. Bonus: its CastleDB enum sync reads Hide's live database, unsaved changes included.

## Running in NW.js (instead of Electron)

The renderer can also run standalone in [NW.js](https://nwjs.io/), without the Electron main process:

```
nw app/nwjs
```

# Contributing

You can read the upstream Pull Request guidelines here:
https://github.com/deepnight/ldtk/wiki#pull-request-guidelines

# Related tools & licences

 - Tileset images: see [README](app/extraFiles/samples/README.md) in samples
 - Haxe: https://haxe.org
 - Heaps.io: https://heaps.io/
 - Electron: https://www.electronjs.org/
 - JQuery: https://jquery.com
 - MarkedJS: https://marked.js.org/
 - SVG icons from https://material.io
 - Default palette: "*Endesga32*" by Endesga (https://lospec.com/palette-list/endesga-32)
 - Default color blind palette: "*Colorblind 16*" by FilipWorks (https://github.com/filipworksdev/colorblind-palette-16)
