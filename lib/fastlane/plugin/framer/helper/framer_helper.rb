module Fastlane
  module Helper
    class FramerHelper
      # class methods that you define here become available in your action
      # as `Helper::FramerHelper.your_method`
      #
      def self.show_message
        UI.message("Hello from the framer plugin helper!")
      end
    end
  end
end
