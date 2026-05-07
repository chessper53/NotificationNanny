cask "notificationnanny" do
  version "4.0.0"
  sha256 "eaa4999bbe86d21926dee750fb4e7ffac4e31493e89166f1760e3dd777d7a59e"

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
    "~/Library/Application Support/com.notificationnanny.app",
    "~/Library/Containers/com.notificationnanny.app",
  ]
end
