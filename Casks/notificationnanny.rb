cask "notificationnanny" do
  version "6.4.0"
  sha256 "b641fd1d4d02268222367ffed5c919061b923c50dd25d1228651086972cf68b0"

  url "https://github.com/chessper53/NotificationNanny/releases/download/v#{version}/NotificationNanny-#{version}.zip"
  name "NotificationNanny"
  desc "Reposition macOS notification banners to any corner of any display"
  homepage "https://github.com/chessper53/NotificationNanny"

  depends_on macos: ">= :ventura"

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
