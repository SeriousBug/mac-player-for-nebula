# Player for Nebula

A native macOS app for watching videos on [Nebula](https://nebula.tv).

## Not affiliated with Nebula

**This project is not affiliated with, endorsed by, or sponsored by Nebula or Standard Broadcast LLC.** "Nebula" is a trademark of its owner and is used here only to describe what the app works with.

You need your own Nebula subscription to use this app.

## How it works

The app does not bypass any security measures. It does the same thing your web browser does when you watch Nebula at nebula.tv:

- You sign in on the regular Nebula login page, shown inside the app.
- The app uses the session from that sign-in to call the same APIs the Nebula website calls.
- Videos play from the same streams the website plays, using the macOS video player.

The app does not download videos or remove DRM. It can't play anything your account can't already watch.

## Features

- Latest videos from channels you follow
- Channel pages with follow buttons and exclusivity filters
- Watch later and watch history
- Resumes playback where you left off and saves your progress while you watch

## Requirements

- macOS 26 or later
- A Nebula subscription

## Building

Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) and [just](https://github.com/casey/just), then run:

```sh
just run
```

This generates the Xcode project, builds the app, and launches it. Run `just open` to open the project in Xcode.

## License

MIT. See [LICENSE](LICENSE).
