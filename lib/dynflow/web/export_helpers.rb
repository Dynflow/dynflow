module Dynflow
  module Web
    module ExportHelpers

      def set_download_headers(filename)
        response.headers['Content-Disposition'] = "attachment; filename=#{filename}"
        response.headers['Content-Type'] = 'application/octet-stream'
        response.headers['Content-Transfer-Encoding'] = 'binary'
      end

    end
  end
end
