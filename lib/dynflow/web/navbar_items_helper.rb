module Dynflow
  module Web
    module NavbarItemsHelper
      module Link

        def self.link_back(url)
          @@link_back ||= url
        end
      end

      def back
        Link.link_back request.referrer
      end
    end
  end
end
