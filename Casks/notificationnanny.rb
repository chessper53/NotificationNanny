cask "notificationnanny" do
  version "8.0.1"
  sha256 "dac9d9e0f7d4eae2b0ac15e2af7180820bb435aeb0ec91761bb38d6fb8fb48ac"

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
