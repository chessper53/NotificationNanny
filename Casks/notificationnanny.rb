cask "notificationnanny" do
  version "7.6.1"
  sha256 "7fc5fe13129806f3069c465300a17d6062af49c5bdd5c35a9dfdaab440835988"

  url "https://github.com/chessper53/NotificationNanny/releases/download/v#{version}/NotificationNanny-#{version}.zip"
  name "NotificationNanny"
  desc "Control the position, style, and behavior of macOS notification banners"
  homepage "https://github.com/chessper53/NotificationNanny"

  depends_on macos: :sonoma

  app "NotificationNanny.app"

  postflight do
    system_command "/usr/bin/xattr",
      args: ["-d", "-r", "com.apple.quarantine", "#{appdir}/NotificationNanny.app"]
  end

  zap trash: [
    "~/Library/Preferences/com.notificationnanny.app.plist",
    "~/Library/Application Support/NotificationNanny",
    "~/Library/Application Support/com.notificationnanny.app",
    "~/Library/Containers/com.notificationnanny.app",
  ]
end
