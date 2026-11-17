# GitHub release, Homebrew cask, updates

## GitHub release

```bash
gh release create v1.2.0 dist/Example.dmg --repo user/example-app \
  --title "Example App 1.2.0" --notes-file notes.md
```
Release only after `stapler validate` and `spctl` pass. Upload the exact file whose sha256 you print.
`--prerelease` keeps `latest` stable for beta builds.

## Homebrew tap and cask

A tap is a repo named `homebrew-<tap>` containing `Casks/<name>.rb`; users run `brew tap user/tap`.

```ruby
cask "example-app" do
  version "1.2.0"
  sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  url "https://github.com/user/example-app/releases/download/v#{version}/Example.dmg"
  name "Example App"
  desc "One line about what it does"
  homepage "https://example.com"

  depends_on macos: ">= :ventura"
  # depends_on formula: "ffmpeg"   # only if the app really shells out to it

  app "Example App.app"

  zap trash: [
    "~/Library/Application Support/com.example.app",
    "~/Library/Preferences/com.example.app.plist",
  ]
end
```

Bump, from the tap checkout:
```bash
SHA=$(shasum -a 256 Example.dmg | cut -d' ' -f1)
sed -i '' -E "s/^  version \".*\"/  version \"1.2.0\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/example-app.rb
brew audit --cask --online Casks/example-app.rb
git commit -am "example-app 1.2.0" && git push
```
Users: `brew update && brew upgrade --cask example-app`.
Docs: https://docs.brew.sh/Cask-Cookbook , https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap

Notes:
- `depends_on macos:` must match `LSMinimumSystemVersion` and the `MACOSX_DEPLOYMENT_TARGET` you built with.
- Apple Silicon only build: add `depends_on arch: :arm64`.
- Put the tag in the URL (`v#{version}`); a moving "latest" URL breaks the checksum for old versions.
- The sha256 is that of the **stapled** DMG you uploaded. Stapling after hashing changes the file.
- A third-party tap may need to be trusted by the user on recent Homebrew; say so in install notes.

## Updates inside the app

Homebrew users update through the cask. For everyone else use Sparkle (https://sparkle-project.org):
EdDSA key, an `appcast.xml` next to the release, `SUFeedURL` in Info.plist. Sparkle's helpers
(`Autoupdate`, `Updater.app`, XPC services) are nested code: sign them inside-out like the rest,
never with `--deep`.
