cask "notificationnanny" do
  version "7.0.0"
  sha256 "PLACEHOLDER_SHA256"

  url "https://github.com/chessper53/NotificationNanny/releases/download/v#{version}/NotificationNanny-#{version}.zip"
  name "NotificationNanny"
  desc "Control the position, style, and behavior of macOS notification banners"
  homepage "https://github.com/chessper53/NotificationNanny"

  depends_on macos: ">= :sonoma"

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
