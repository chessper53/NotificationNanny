cask "notificationnanny" do
  version "0.1.0"
  sha256 :no_check  # replace with the SHA256 of NotificationNanny-<version>.zip after release

  # Update GITHUB_USER once you publish the repo.
  url "https://github.com/GITHUB_USER/NotificationNanny/releases/download/v#{version}/NotificationNanny-#{version}.zip"
  name "NotificationNanny"
  desc "Reposition macOS notification banners to any corner of any display"
  homepage "https://github.com/GITHUB_USER/NotificationNanny"

  depends_on macos: ">= :ventura"

  app "NotificationNanny.app"

  zap trash: [
    "~/Library/Preferences/com.notificationnanny.app.plist",
    "~/Library/Application Scripts/com.notificationnanny.app",
    "~/Library/Containers/com.notificationnanny.app",
  ]
end
