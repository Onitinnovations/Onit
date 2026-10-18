# OnIt mobile development

This folder contains a React Native app using Expo and TypeScript.
The application routes are in `src/app`.

## Run the app

From this folder in PowerShell:

```powershell
npm.cmd start
```

Install Expo Go on your phone and scan the QR code. The phone and computer
should be on the same network. For the browser preview, run `npm.cmd run web`.

## Verify the project

```powershell
npm.cmd run typecheck
npm.cmd run lint
npm.cmd run doctor
```

## Build Android or iOS with EAS

EAS builds native binaries in the cloud. Sign in to your own Expo account,
then configure the project and choose the package identifiers when prompted:

```powershell
npx.cmd eas-cli@24.12.1 login
npx.cmd eas-cli@24.12.1 build:configure
npm.cmd run build:android
```

The Android preview profile generates an installable APK. For a production
Android build, use `npx.cmd eas-cli@24.12.1 build --platform android --profile production`.
For iOS, use `npm.cmd run build:ios`; device distribution requires Apple
developer credentials. No cloud build has been submitted during installation.

## Local native builds

Android Studio, the Android SDK, and a compatible Java JDK are separate
requirements for compiling Android locally or running an Android emulator.
They are not required for Expo Go, browser previews, or EAS cloud builds.
Local iOS compilation and the iOS simulator require macOS and Xcode.

## Supabase

Copy `.env.example` to `.env.local` and fill in your Supabase project URL and
publishable key from the project dashboard. Expo includes `EXPO_PUBLIC_`
variables in the app bundle: use only the public publishable key, never a
secret or service-role key. Restart Expo after changing the values.

Import the shared client with `import { supabase } from '@/lib/supabase';`.
Native auth sessions persist with AsyncStorage; web uses browser storage.

## Reinstall dependencies

Node.js LTS and Git are already available on this computer. The lockfile pins
the project dependencies; restore them with `npm.cmd ci`.

Using `npm.cmd` and `npx.cmd` avoids PowerShell script execution policy issues.

## Installation verification

TypeScript, ESLint, and all 21 Expo Doctor checks passed. Android and iOS
Hermes bundles and the web static export compiled successfully. These checks
do not replace testing a native binary on a device.

npm reports 29 dependency advisories (11 moderate, 18 high) in the installed
project. Its suggested fixes include incompatible Expo and React Native
versions, so the SDK-compatible versions have been retained. Review these
advisories before a production release.
