cask "notificationnanny" do
  version "0.2.0"
  sha256 "aa93eb69a96f0afb9efd89e447f16798d9a4fb17c027a2d8bed2ea0128111b0c"

  url "https://github.com/chessper53/NotificationNanny/releases/download/v#{version}/NotificationNanny-#{version}.zip"
  name "NotificationNanny"
  desc "Reposition macOS notification banners to any corner of any display"
  homepage "https://github.com/chessper53/NotificationNanny"

  depends_on macos: ">= :ventura"

  app "NotificationNanny.app"

  zap trash: [
    "~/Library/Preferences/com.notificationnanny.app.plist",
    "~/Library/Application Support/com.notificationnanny.app",
    "~/Library/Containers/com.notificationnanny.app",
  ]
end
