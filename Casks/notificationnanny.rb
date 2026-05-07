cask "notificationnanny" do
  version "3.0.0"
  sha256 "2c7aaaa8edb85da95b9172680ea5a3a386765f68b71ee440b4f605972fce201c"

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
