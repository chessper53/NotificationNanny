cask "notificationnanny" do
  version "5.0.0"
  sha256 "3d28847966917d7f314ce1b42bbb18272807bcb0e2277d1d780488bbe58dd5d3"

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
