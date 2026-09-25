cask "notificationnanny" do
  version "8.0.2"
  sha256 "72bdb20d310b7715139ca23bac5a802eeafcbdff188d5bb67c5a9caa811e7326"

  url "https://github.com/chessper53/NotificationNanny/releases/download/v#{version}/NotificationNanny-#{version}.zip"
  name "NotificationNanny"
  desc "Control the position, style, and behavior of macOS notification banners"
  homepage "https://github.com/chessper53/NotificationNanny"

  depends_on macos: :sonoma

  app "NotificationNanny.app"

  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-d", "-r", "com.apple.quarantine", "{{appdir}}/NotificationNanny.app"],
        must_succeed: false
  end

  zap trash: [
    "~/Library/Preferences/com.notificationnanny.app.plist",
    "~/Library/Application Support/NotificationNanny",
    "~/Library/Application Support/com.notificationnanny.app",
    "~/Library/Containers/com.notificationnanny.app",
  ]
end
